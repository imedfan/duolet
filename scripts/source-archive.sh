#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
python3 - <<'PY'
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
root = Path.cwd()
include = ['Sources', 'Tests', 'Config', 'Resources', 'Duolet.xcodeproj', 'scripts',
           'docs', '.github', 'Package.swift', 'README.md', 'LICENSE', 'CONTRIBUTING.md', '.gitignore']
with ZipFile(root / 'dist/Duolet-1.0.0-source.zip', 'w', ZIP_DEFLATED) as archive:
    for name in include:
        path = root / name
        for file in sorted(path.rglob('*')) if path.is_dir() else [path]:
            if not file.is_file() or any(part in {'xcuserdata', '.DS_Store'} for part in file.parts):
                continue
            archive.write(file, Path('Duolet') / file.relative_to(root))
PY
(cd dist && shasum -a 256 Duolet-1.0.0-universal.dmg Duolet-1.0.0-source.zip > SHA256SUMS)
echo "Prepared: dist/Duolet-1.0.0-source.zip"
