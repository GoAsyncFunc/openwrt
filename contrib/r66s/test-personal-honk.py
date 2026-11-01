#!/usr/bin/env python3
import base64
import gzip
import importlib.util
from pathlib import Path
import sqlite3
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('prepare', Path(__file__).with_name('prepare-personal-honk.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PersonalHonkTest(unittest.TestCase):
    def test_authenticated_cached_state_and_permissions(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with sqlite3.connect(root / 'state.db') as db:
                for table in ('admin', 'subscription_body', 'dns_answer', 'delay_sample'):
                    db.execute(f'CREATE TABLE {table} (value TEXT)')
                    db.execute(f'INSERT INTO {table} VALUES (?)', ('fixture',))
                db.execute('CREATE TABLE revision (number INTEGER PRIMARY KEY, parent INTEGER)')
                db.executemany('INSERT INTO revision VALUES (?, ?)', [(1, None), (2, 1)])
                db.execute('CREATE TABLE head (id INTEGER PRIMARY KEY, active INTEGER)')
                db.execute('INSERT INTO head VALUES (1, 2)')
            bundle = {
                'config': "dns {\n bind: 'tcp+udp://127.0.0.1:5353'\n}\nsubscription {\n}\n",
                'system': "password_auth: true\nallow_anonymous_loopback: false\nbootstrap_resolver: '127.0.0.1:5336'\n",
                'mosdns_whitelist': 'domain:example.net\n',
                'mosdns_config': 'plugins: []\n',
                'database': base64.b64encode(gzip.compress((root / 'state.db').read_bytes())).decode(),
            }
            module.prepare(bundle, root / 'files')
            state = root / 'files/etc/honk/state/honk.db'
            self.assertEqual(state.stat().st_mode & 0o777, 0o600)
            self.assertEqual((root / 'files/etc/mosdns/rule/whitelist.txt').read_text(),
                             'domain:example.net\n')
            self.assertEqual((root / 'files/etc/mosdns/config_custom.yaml').read_text(),
                             'plugins: []\n')
            with sqlite3.connect(state) as db:
                self.assertEqual(db.execute('SELECT count(*) FROM admin').fetchone()[0], 1)
                self.assertEqual(db.execute('SELECT count(*) FROM subscription_body').fetchone()[0], 1)
                self.assertEqual(db.execute('SELECT count(*) FROM dns_answer').fetchone()[0], 0)
                self.assertEqual(db.execute('SELECT number, parent FROM revision').fetchall(), [(2, None)])
            # The global block is now in the main source, not the native API include.
            bundle['system'] = bundle['system'].replace("bootstrap_resolver: '127.0.0.1:5336'\n", '')
            bundle['config'] += "global {\n bootstrap_resolver: '127.0.0.1:5336'\n}\n"
            module.prepare(bundle, root / 'main-global')
            bundle['config'] = bundle['config'].split('global {')[0]
            with self.assertRaises(ValueError):
                module.prepare(bundle, root / 'rejected')
            bundle['system'] = 'password_auth: false'
            with self.assertRaises(ValueError):
                module.prepare(bundle, root / 'rejected')
            bundle['system'] = "password_auth: true\nallow_anonymous_loopback: false\nbootstrap_resolver: '127.0.0.1:5336'"
            bundle['database'] = base64.b64encode(gzip.compress(b'broken SQLite')).decode()
            with self.assertRaises(sqlite3.DatabaseError):
                module.prepare(bundle, root / 'rejected')


if __name__ == '__main__':
    unittest.main()
