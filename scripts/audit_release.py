#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Check source inputs and optional current-version archives for private data."""
from pathlib import Path
import plistlib
import re
import subprocess
from zipfile import ZipFile
from export_source import ROOT, release_files

PATTERNS = {
    'absolute user directory': re.compile(r'/Users/[A-Za-z0-9_.-]+/'),
    'private IPv4 address': re.compile(r'\b(?:10(?:\.\d{1,3}){3}|192\.168(?:\.\d{1,3}){2}|172\.(?:1[6-9]|2\d|3[01])(?:\.\d{1,3}){2})\b'),
    'specific Brother hostname': re.compile(r'\bBRW[0-9a-fA-F]{12}\b'),
    'fixed certificate fingerprint': re.compile(r'\b[0-9a-fA-F]{64}\b'),
    'private key': re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
}

def audit_source(files):
    for path in files:
        text = path.read_text(encoding='utf-8')
        for label, pattern in PATTERNS.items():
            if pattern.search(text):
                raise ValueError(f'{label} in {path.relative_to(ROOT)}')
    print(f'PASS: {len(files)} allowlisted source files; no known private-data patterns')

def main():
    audit_source(release_files())
    version = plistlib.loads((ROOT / 'Info.plist').read_bytes())['CFBundleShortVersionString']
    source = ROOT / 'dist' / f'Scan-Connector-for-Mac-{version}-Source.zip'
    if source.exists():
        with ZipFile(source) as archive:
            expected = {str(Path('scan-connector-for-mac') / p.relative_to(ROOT)) for p in release_files()}
            if set(archive.namelist()) != expected:
                raise ValueError('Source archive differs from the allowlist')
            for name in archive.namelist():
                for label, pattern in PATTERNS.items():
                    if pattern.search(archive.read(name).decode('utf-8')):
                        raise ValueError(f'{label} in source archive: {name}')
        print('PASS: source archive contains exactly the allowlisted files')
    app = ROOT / 'dist' / 'Scan Connector for Mac.app'
    if app.exists():
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        binary = app / 'Contents/MacOS/Scan Connector for Mac'
        linked = subprocess.check_output(['otool', '-L', str(binary)], text=True)
        for line in linked.splitlines()[1:]:
            dependency = line.strip().split(' (', 1)[0]
            if not dependency.startswith(('/System/Library/', '/usr/lib/')):
                raise ValueError(f'Non-system runtime dependency: {dependency}')
        allowed = {'Contents/Info.plist','Contents/MacOS/Scan Connector for Mac',
                   'Contents/Resources/AppIcon.icns','Contents/Resources/LICENSE.txt',
                   'Contents/Resources/NOTICE.txt','Contents/_CodeSignature/CodeResources'}
        actual = {str(p.relative_to(app)) for p in app.rglob('*') if p.is_file()}
        if actual != allowed:
            raise ValueError(f'Unexpected app contents: {actual.symmetric_difference(allowed)}')
        print('PASS: signed app has only expected files and Apple system dependencies')
    package = ROOT / 'dist' / f'Scan-Connector-for-Mac-{version}-Apple-Silicon.zip'
    if package.exists():
        with ZipFile(package) as archive:
            for name in archive.namelist():
                if name.lower().endswith(('.pdf','.jpg','.jpeg','.png','.dylib','.py','.p12')):
                    raise ValueError(f'Unexpected app archive file: {name}')
        print('PASS: app archive contains no scans or third-party runtime files')

if __name__ == '__main__':
    main()
