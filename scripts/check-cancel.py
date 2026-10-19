import hashlib
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import time
import uuid

root = Path(__file__).resolve().parents[1]
binary = Path(sys.argv[1]).resolve()
work = root / '.runtime' / ('cancel-check-' + uuid.uuid4().hex[:8])
work.mkdir(parents=True)
source, output = work / 'source.pdf', work / 'source_ocr.pdf'
env = {**os.environ, 'BOOKSIDE_DATA_DIR': str(work / 'data')}
subprocess.run(['swift', str(root / 'scripts/make-fixture.swift'), str(source), '20'], env=env, check=True, capture_output=True)
original_hash = hashlib.sha256(source.read_bytes()).hexdigest()
book = json.loads(subprocess.check_output([str(binary), 'import', str(source)], env=env, text=True))[0]
process = subprocess.Popen([str(binary), 'ocr', book['id'], '--output', str(output)], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
selector = selectors.DefaultSelector(); selector.register(process.stderr, selectors.EVENT_READ)
deadline = time.monotonic() + 15
started = False
lines = []
while time.monotonic() < deadline:
    if selector.select(timeout=1):
        line = process.stderr.readline(); lines.append(line)
        if 'Mac에서' in line:
            started = True
            process.send_signal(signal.SIGINT)
            break
assert started, ''.join(lines)
out, err = process.communicate(timeout=20)
assert process.returncode != 0 and '취소' in err, (process.returncode, out, err)
assert not output.exists()
assert not list(work.glob('*.partial.pdf'))
assert hashlib.sha256(source.read_bytes()).hexdigest() == original_hash
report = {'cancelled': True, 'original_preserved': True, 'no_partial_output': True}
(root / '.runtime/cancel-check-result.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report))
