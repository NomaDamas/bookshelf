"""Verify the app's scoped MCP route using check-ocr.py's authored fixture; no AI account."""
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[1]
state = json.loads((root / '.runtime/ocr-check-result.json').read_text())
binary = str(Path(sys.argv[1]).resolve()) if len(sys.argv) > 1 else state['binary']
process = subprocess.Popen(
    [binary, 'reading-mcp', state['book_id'], 'range', '1', '1'],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    text=True, bufsize=1, env={**os.environ, 'BOOKSIDE_DATA_DIR': state['data_dir']},
)
selector = selectors.DefaultSelector()
selector.register(process.stdout, selectors.EVENT_READ)
serial = 0


def request(method, params=None, notification=False):
    global serial
    serial += 1
    message = {'jsonrpc': '2.0', 'method': method, 'params': params or {}}
    if not notification:
        message['id'] = serial
    process.stdin.write(json.dumps(message) + '\n')
    process.stdin.flush()
    if notification:
        return
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        if selector.select(1):
            line = process.stdout.readline()
            if not line:
                raise RuntimeError('Reading server disconnected')
            reply = json.loads(line)
            if reply.get('id') == serial:
                assert 'error' not in reply, reply
                return reply['result']
    raise TimeoutError(method)


def call(tool, arguments):
    return request('tools/call', {'name': tool, 'arguments': arguments})


try:
    request('initialize', {
        'protocolVersion': '2025-06-18',
        'capabilities': {'experimental': {'codex/auth-change': {}}},
        'clientInfo': {'name': 'bookside-reading-check', 'version': '1'},
    })
    request('notifications/initialized', notification=True)
    tools = request('tools/list')['tools']
    assert {t['name'] for t in tools} == {'get_book_overview', 'search_book', 'read_pages', 'get_reading_coverage'}
    assert all(t['annotations']['readOnlyHint'] for t in tools)
    assert all('book_id' not in t['inputSchema'].get('properties', {}) for t in tools)
    overview = call('get_book_overview', {})
    assert not overview.get('isError'), overview
    assert json.loads(overview['content'][0]['text'])['pageCount'] == 2
    assert call('read_pages', {'start_page': 2}).get('isError')
    assert call('read_pages', {'start_page': 1, 'book_id': 'another-book'}).get('isError')
    assert call('list_books', {}).get('isError')
    search = call('search_book', {'query': '서\t재'})
    assert not search.get('isError'), search
    found = json.loads(search['content'][0]['text'])
    assert found['matches'] and all(m['page'] == 1 for m in found['matches'])
    assert found['reading']['readPages'] == []
    read = call('read_pages', {'start_page': 1})
    assert not read.get('isError'), read
    page = json.loads(read['content'][0]['text'])
    assert '서재' in page['pages'][0]['text']
    coverage = json.loads(call('get_reading_coverage', {})['content'][0]['text'])['reading']
    assert coverage['readPages'] == [1] and coverage['sourcePages'] == [1]
    report = {'read_only_tools': len(tools), 'codex_handshake': True, 'outside_range_rejected': True,
              'other_book_rejected': True, 'scoped_search': True, 'coverage_not_inferred_from_search': True}
    (root / '.runtime/reading-mcp-check-result.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, indent=2))
finally:
    process.stdin.close()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.terminate()
        process.wait(timeout=5)
