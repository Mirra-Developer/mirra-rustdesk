#!/usr/bin/env python3
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PREFERENCES = Path.home() / 'Library/Preferences'
SOURCE = PREFERENCES / 'com.carriez.RustDesk'
DEST = PREFERENCES / 'com.carriez.MirraRustDeskTest'
NAME = 'MirraRustDeskTest'


def main():
    if DEST.exists():
        raise SystemExit('Test profile already exists; existing settings will not be overwritten.')
    DEST.mkdir(mode=0o700)
    text = (SOURCE / 'RustDesk2.toml').read_text()
    text = re.sub(r'^mirra-auto-id-routing\s*=.*\n?', '', text, flags=re.M)
    text = text.replace('[options]\n', "[options]\nmirra-auto-id-routing = 'Y'\n", 1)
    (DEST / (NAME + '2.toml')).write_text(text)
    peers = DEST / 'peers'
    peers.mkdir(mode=0o700)
    ids = []
    for source in sorted((SOURCE / 'peers').glob('*.toml')):
        if '@' not in source.stem:
            continue
        peer_id, server = source.stem.split('@', 1)
        if not peer_id.isdigit() or server not in ['us.rustdesk.mirra-xr.com', 'rustdesk.mirra-xr.com']:
            continue
        peer = source.read_text()
        peer = re.sub(r'^other-server-key\s*=.*\n?', '', peer, flags=re.M)
        (peers / (peer_id + '.toml')).write_text(peer)
        ids.append(peer_id)
    (DEST / (NAME + '_local.toml')).write_text(
        'fav = ' + json.dumps(ids) + "\n\n[ui_flutter]\npeer-tab-index = '3'\n"
    )
    for file in DEST.rglob('*'):
        if file.is_file():
            file.chmod(0o600)
    print('Isolated profile:', DEST)
    print('Imported plain IDs:', ', '.join(ids))
    print('No Account token or user_info was copied. Sign in through Account in the test app.')


if __name__ == '__main__':
    main()
