"""Protocol integration check: a real stdio MCP client, no model request or credentials."""
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[1]
state = json.loads((root / '.runtime/ocr-check-result.json').read_text())
if len(sys.argv) > 1:
    state['binary'] = str(Path(sys.argv[1]).resolve())
env = {**os.environ, 'BOOKSHELF_DATA_DIR': state['data_dir']}
stderr = (root / '.runtime/mcp-stderr.log').open('w')
process = subprocess.Popen([state['binary'], 'mcp'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr, text=True, bufsize=1, env=env)
selector = selectors.DefaultSelector(); selector.register(process.stdout, selectors.EVENT_READ)
counter = 0

def send(method, params=None, notification=False):
    global counter
    counter += 1
    message = {'jsonrpc': '2.0', 'method': method}
    if params is not None:
        message['params'] = params
    if not notification:
        message['id'] = counter
    process.stdin.write(json.dumps(message) + '\n'); process.stdin.flush()
    if notification:
        return
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        if selector.select(timeout=1):
            line = process.stdout.readline()
            if not line:
                raise RuntimeError('MCP closed unexpectedly')
            response = json.loads(line)
            if response.get('id') == counter:
                assert 'error' not in response, response
                return response['result']
    raise TimeoutError(method)

try:
    init = send('initialize', {'protocolVersion': '2025-11-25', 'capabilities': {}, 'clientInfo': {'name': 'bookshelf-integration-check', 'version': '1'}})
    send('notifications/initialized', notification=True)
    tools = send('tools/list')['tools']
    assert len(tools) == 5
    assert all(t['annotations']['readOnlyHint'] for t in tools)
    book_id = state['book_id']
    responses = {}
    for name, arguments in [('list_books', {'query': 'scan'}), ('read_page', {'book_id': book_id, 'page': 1}), ('search_book', {'book_id': book_id, 'query': '메모'}), ('get_notes', {'book_id': book_id}), ('get_reading_context', {})]:
        result = send('tools/call', {'name': name, 'arguments': arguments})
        assert not result.get('isError'), result
        responses[name] = json.loads(result['content'][0]['text'])
    assert '서재' in responses['read_page']['text']
    assert responses['search_book']['matches']
    assert responses['get_notes']['notebook'].startswith('OCR 전에 쓴 메모')
    assert responses['get_reading_context']['page'] == 2
    invalid = send('tools/call', {'name': 'read_page', 'arguments': {'book_id': book_id, 'page': 0}})
    assert invalid.get('isError')
    report = {'protocol': init['protocolVersion'], 'tools': [t['name'] for t in tools], 'all_read_only': True, 'all_calls_passed': True, 'invalid_page_rejected': True}
    (root / '.runtime/mcp-check-result.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))
finally:
    process.stdin.close()
    try: process.wait(timeout=5)
    except subprocess.TimeoutExpired: process.terminate(); process.wait(timeout=5)
    stderr.close()
