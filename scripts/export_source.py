#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Create a source-only archive from explicit release inputs."""
from pathlib import Path
import plistlib
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
TOP_LEVEL = (
    'README.md', 'LICENSE', 'NOTICE',
    'SECURITY.md', 'THIRD_PARTY.md', 'CONTRIBUTING.md', 'DESIGN.md',
    'Info.plist', 'Icon.swift', 'build.sh', 'package.sh',
    'requirements-dev.txt', 'test_integration.py', '.gitignore', '.gitattributes',
)
SOURCE_FILES = (
    'Sources/Protocol.swift', 'Sources/Appearance.swift', 'Sources/Receiver.swift',
    'Sources/Model.swift', 'Sources/Views.swift', 'Sources/Tests.swift', 'Sources/main.swift',
    'scripts/export_source.py', 'scripts/audit_release.py', '.github/workflows/ci.yml',
)

def release_files():
    files = [ROOT / name for name in TOP_LEVEL + SOURCE_FILES]
    for path in files:
        if path.is_symlink() or not path.is_file():
            raise ValueError(f'Missing or unsafe release input: {path.relative_to(ROOT)}')
    return files

def main():
    from audit_release import audit_source
    files = release_files()
    audit_source(files)
    version = plistlib.loads((ROOT / 'Info.plist').read_bytes())['CFBundleShortVersionString']
    target = ROOT / 'dist' / f'Scan-Connector-for-Mac-{version}-Source.zip'
    target.parent.mkdir(exist_ok=True)
    with ZipFile(target, 'w', ZIP_DEFLATED) as archive:
        for path in files:
            archive.write(path, Path('scan-connector-for-mac') / path.relative_to(ROOT))
    print(f'Exported {len(files)} allowlisted source files: {target}')

if __name__ == '__main__':
    main()
