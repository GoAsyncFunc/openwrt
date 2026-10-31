#!/usr/bin/env python3
"""Prepare a private Honk overlay; input and parser errors must never be logged."""

import base64
from contextlib import closing
import gzip
import json
import os
from pathlib import Path
import sqlite3
import sys
import tempfile


def write_private(path, content, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content if isinstance(content, bytes) else content.encode())
    path.chmod(mode)


def prepare(bundle, overlay):
    config, system = bundle['config'], bundle['system']
    if "bind: 'tcp+udp://127.0.0.1:5353'" not in config or 'subscription {' not in config:
        raise ValueError('Missing Honk DNS listener or subscription')
    if 'password_auth: true' not in system or 'allow_anonymous_loopback: false' not in system:
        raise ValueError('Authenticated native API required')
    if "bootstrap_resolver: '127.0.0.1:5336'" not in system:
        raise ValueError('Independent node bootstrap DNS required')
    database = gzip.decompress(base64.b64decode(bundle['database'], validate=True))
    if len(database) > 4 * 1024 * 1024:
        raise ValueError('Oversized state database')
    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp) / 'honk.db'
        path.write_bytes(database)
        with closing(sqlite3.connect(path)) as db:
            if db.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
                raise ValueError('Invalid state database')
            if not db.execute('SELECT count(*) FROM admin').fetchone()[0]:
                raise ValueError('Missing initialized administrator')
            if not db.execute('SELECT count(*) FROM subscription_body').fetchone()[0]:
                raise ValueError('Missing cached subscription for first boot')
            # Keep authentication and subscription cache, omit runtime DNS/delay history.
            db.execute('DELETE FROM dns_answer')
            db.execute('DELETE FROM delay_sample')
            db.commit()
            db.execute('VACUUM')
        database = path.read_bytes()
    for name in ('config.dae', 'managed-config.dae'):
        write_private(overlay / 'etc/honk' / name, config)
    write_private(overlay / 'etc/honk/system.dae', system)
    if 'mosdns_whitelist' in bundle:
        write_private(overlay / 'etc/mosdns/rule/whitelist.txt', bundle['mosdns_whitelist'])
    write_private(overlay / 'etc/honk/state/honk.db', database)
    (overlay / 'etc/honk/state').chmod(0o700)
    write_private(overlay / 'etc/config/honk', """config honk 'main'
    option enabled '1'
    option boot_enabled '1'
    option initialized '1'
    option config_mode 'managed'
    option config_file '/etc/honk/config.dae'
    option listen_port '9527'
    option clash_api_enabled '0'
    option clash_api_port '9090'
    option clash_api_secret ''
    option lan_network 'lan'
    option geo_auto '0'
""")
    write_private(overlay / 'etc/uci-defaults/99-r66s-personal-honk', """#!/bin/sh
uci set honk.main.enabled='1'
uci set honk.main.initialized='1'
uci commit honk
uci set openclash.config.enable='0'
uci set openclash.config.auto_update='0'
uci commit openclash
/etc/init.d/openclash disable
/etc/init.d/honk enable
/etc/init.d/mosdns enable
/etc/init.d/adguardhome enable
exit 0
""", 0o700)


if __name__ == '__main__':
    os.umask(0o077)
    try:
        prepare(json.load(sys.stdin), Path(sys.argv[1] if len(sys.argv) > 1 else 'files'))
    except Exception:
        sys.exit('Private Honk input is invalid; details suppressed')
    print('Private Honk overlay prepared (contents suppressed)')
