from pathlib import Path
import json
import shutil
import sys

output = Path(sys.argv[1]) / 'PiAgent'
output.mkdir(parents=True, exist_ok=True)
root = Path.cwd()
agent = root / 'Sources/BookshelfAgent'
metadata = {'outputs': {}}
for name in ('metafile.json', 'renderer-metafile.json'):
    metadata['outputs'].update(json.loads((root / 'dist/agent' / name).read_text())['outputs'])
seen = set()
index = []
for bundle in metadata['outputs'].values():
    for source, contribution in bundle.get('inputs', {}).items():
        if not contribution.get('bytesInOutput') or 'node_modules' not in source:
            continue
        candidate = root / source
        folder = (candidate if candidate.exists() else agent / source).resolve().parent
        while folder != folder.parent:
            manifest = folder / 'package.json'
            if manifest.is_file():
                data = json.loads(manifest.read_text())
                if data.get('name') and data.get('version'):
                    break
            folder = folder.parent
        else:
            raise RuntimeError('Cannot identify bundled dependency: ' + source)
        name, version = data['name'], data['version']
        if (name, version) in seen:
            continue
        seen.add((name, version))
        destination = output / (name.replace('/', '__') + '-' + version)
        destination.mkdir(exist_ok=True)
        notices = [p for p in folder.iterdir() if p.is_file() and p.name.lower().startswith(('license', 'licence', 'notice'))]
        if not notices and name.startswith('@earendil-works/') and version == '0.85.1':
            # The pinned monorepo packages omit their shared license from npm tarballs.
            notices = [agent / 'LICENSE.pi.txt']
        if not notices and name == 'fastdom' and version == '1.0.12':
            # This package includes the complete MIT notice in its published README.
            notices = [folder / 'README.md']
        if not notices:
            raise RuntimeError('Missing license text for bundled dependency: ' + name)
        for notice in notices:
            shutil.copyfile(notice, destination / notice.name)
        index.append({'name': name, 'version': version, 'license': data.get('license'), 'notices': [p.name for p in notices]})
(output / 'packages.json').write_text(json.dumps(sorted(index, key=lambda p: p['name']), indent=2) + '\n')
print(f'Copied notices for {len(index)} dependencies actually included in the agent bundle.')
