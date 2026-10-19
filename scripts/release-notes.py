"""Render a tagged CHANGELOG section and the distribution status for GitHub."""

import json
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
metadata = json.loads((root / "Sources/BookshelfCore/Resources/AppMetadata.json").read_text())
tag = sys.argv[1]
if tag != "v" + metadata["version"]:
    raise SystemExit("Release tag and metadata version disagree")
changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")
match = re.search(r"^## \[" + re.escape(metadata["version"]) + r"\][^\n]*\n(.*?)(?=^## |\Z)", changelog, re.M | re.S)
if not match:
    raise SystemExit("Write the version's CHANGELOG section before tagging")
print(match.group(1).strip())
print(f"""

### Downloads and installation

- `macos-arm64.dmg`: Apple Silicon. `macos-x86_64.dmg`: Intel.
- Verify the matching `.dmg.sha256` file, open the DMG, and drag Bookside.app to Applications.
- `.dSYMs.zip` files hold debug symbols for crash reports; installing does not need them.
- Quit an existing Bookside before replacing it. PDFs, notes, and progress remain in their existing locations.
- OCR tools are external installations; see the OCR guide in the repository.
- See the [installation guide](https://github.com/NomaDamas/bookside/blob/{tag}/docs/01-getting-started.md#install-the-developer-preview)
  for checksum verification and first-launch guidance.

### Distribution status

These CI artifacts are ad-hoc signed developer previews, not Developer ID signed
or notarized by Apple. Gatekeeper can block a downloaded app. Do not treat a valid
checksum as Apple approval. Build from source if you do not want to run a preview.
The JSON file records version, bundle identity, source revision, architecture,
signature mode, notarization status, and the DMG hash.

This is a developer-preview prerelease. Known limitations are listed above.
Published tags and assets are kept unchanged; fixes ship in a new version.
""")
