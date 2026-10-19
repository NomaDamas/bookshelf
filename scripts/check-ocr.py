"""Exercise real Apple OCR against a synthetic raster PDF, never the user's books."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid

root = Path(__file__).resolve().parents[1]
binary = Path(sys.argv[1]).resolve()
run = root / '.runtime' / ('ocr-check-' + uuid.uuid4().hex[:8])
run.mkdir(parents=True)
original = run / 'scan.pdf'
output = run / 'scan_ocr.pdf'
env = {**os.environ, 'BOOKSIDE_DATA_DIR': str(run / 'data')}
subprocess.run(['swift', str(root / 'scripts/make-fixture.swift'), str(original), '2'], check=True, env=env, capture_output=True)

def call(*args, timeout=30):
    result = subprocess.run([str(binary), *args], text=True, capture_output=True, env=env, timeout=timeout)
    (run / 'cli.log').open('a', encoding='utf-8').write(result.stderr)
    if result.returncode:
        raise RuntimeError(result.stderr)
    return json.loads(result.stdout)

before_hash = hashlib.sha256(original.read_bytes()).hexdigest()
book = call('import', str(original))[0]
book_id = book['id']
before = call('inspect', book_id)
assert before['textPages'] == 0, before
call('note-set', book_id, 'OCR 전에 쓴 메모: 원본과 메모를 보존합니다.')
call('position', book_id, '2')
call('bookmark', book_id, '2')
result = call('ocr', book_id, '--language', 'kor', '--output', str(output), timeout=180)
after = call('inspect', book_id)
page = call('read', book_id, '1')
assert '서재' in page['text'] and ('메모' in page['text'] or '원본' in page['text']), page
assert after['pageCount'] == 2 and after['textPages'] == 2, after
assert hashlib.sha256(original.read_bytes()).hexdigest() == before_hash
notes = call('notes', book_id)
assert notes['notebook']['body'].startswith('OCR 전에 쓴 메모')
assert notes['bookmarks'] == [2]
rescan = call('import', str(run))
books = call('books')
assert len(books) == 1 and books[0]['id'] == book_id and books[0]['lastPage'] == 2, books
overwrite = subprocess.run([str(binary), 'ocr', book_id, '--output', str(original)], env=env, capture_output=True, text=True)
assert overwrite.returncode != 0
assert hashlib.sha256(original.read_bytes()).hexdigest() == before_hash
state = {'book_id': book_id, 'data_dir': env['BOOKSIDE_DATA_DIR'], 'source': str(original), 'ocr': str(output), 'before': before, 'after': after, 'source_sha256': before_hash, 'binary': str(binary), 'passed': ['real Apple Vision OCR', 'selectable PDF text', 'original bytes preserved', 'same book identity', 'notebook retained', 'reading page retained', 'bookmark retained', 'overwrite refused', 'rescan deduplicated']}
(root / '.runtime/ocr-check-result.json').write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(state, ensure_ascii=False, indent=2))
