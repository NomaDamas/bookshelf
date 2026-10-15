from pathlib import Path
import shutil
import sys

output = Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)
for dependency in Path('.build/checkouts').iterdir():
    for name in ('LICENSE', 'LICENSE.txt', 'LICENSE.md', 'NOTICE', 'NOTICE.txt'):
        source = dependency / name
        if source.is_file():
            target = output / dependency.name
            target.mkdir(exist_ok=True)
            shutil.copyfile(source, target / name)
shutil.copyfile('LICENSE', output / 'Bookshelf-LICENSE.txt')
