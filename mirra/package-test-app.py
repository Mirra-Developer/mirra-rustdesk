#!/usr/bin/env python3
import argparse
import os
import plistlib
import shutil
import subprocess
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
CLIENT_DIR = SCRIPT_DIR.parent
ROOT = Path(os.environ.get("MIRRA_WORKSPACE", SCRIPT_DIR / "workspace"))
SOURCE = Path('/Applications/RustDesk.app')
DEST = ROOT / 'dist' / 'Mirra RustDesk Test.app'


def exported_symbols(path):
    output = subprocess.check_output(['nm', '-gU', str(path)], text=True)
    return {line.split()[-1] for line in output.splitlines() if line.split()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--replace', action='store_true')
    parser.add_argument('--with-ui', action='store_true')
    args = parser.parse_args()
    core = CLIENT_DIR / 'target/release/liblibrustdesk.dylib'
    if not core.is_file():
        raise SystemExit('Build the Rust core first; no runnable app will be created.')
    ui = ROOT / 'ui-build'
    if args.with_ui and not (ui / 'App.framework/Versions/A/App').is_file():
        raise SystemExit('Build the isolated Flutter UI first.')
    with (SOURCE / 'Contents/Info.plist').open('rb') as stream:
        original = plistlib.load(stream)
    if original.get('CFBundleShortVersionString') != '1.5.0':
        raise SystemExit('The reusable GUI must be RustDesk 1.5.0.')
    old_core = SOURCE / 'Contents/Frameworks/liblibrustdesk.dylib'
    missing = exported_symbols(old_core) - exported_symbols(core)
    if missing:
        raise SystemExit('GUI ABI symbols missing: ' + ', '.join(sorted(missing)))
    if DEST.exists():
        if not args.replace:
            raise SystemExit('Test bundle already exists; use --replace only when it is stopped.')
        shutil.rmtree(DEST)
    DEST.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(SOURCE, DEST, symlinks=True)
    contents = DEST / 'Contents'
    shutil.copy2(core, contents / 'Frameworks/liblibrustdesk.dylib')
    if args.with_ui:
        for name in ['App.framework', 'FlutterMacOS.framework']:
            if not (ui / name).is_dir():
                raise SystemExit(f'Missing compiled UI framework: {name}')
            shutil.rmtree(contents / 'Frameworks' / name)
            shutil.copytree(ui / name, contents / 'Frameworks' / name, symlinks=True)
    (contents / 'MacOS/service').unlink(missing_ok=True)
    shutil.rmtree(contents / '_CodeSignature', ignore_errors=True)
    original.update({
        'CFBundleIdentifier': 'com.mirra.rustdesk.test',
        'CFBundleName': 'Mirra RustDesk Test',
        'CFBundleDisplayName': 'Mirra RustDesk Test',
        'CFBundleURLTypes': [{
            'CFBundleTypeRole': 'Editor',
            'CFBundleURLName': 'com.mirra.rustdesk.test',
            'CFBundleURLSchemes': ['mirrarustdesktest'],
        }],
    })
    with (contents / 'Info.plist').open('wb') as stream:
        plistlib.dump(original, stream)
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(DEST)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(DEST)], check=True)
    print(DEST)


if __name__ == '__main__':
    main()
