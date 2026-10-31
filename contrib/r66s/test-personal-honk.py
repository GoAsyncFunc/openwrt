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
            bundle = {
                'config': "dns {\n bind: 'tcp+udp://127.0.0.1:5353'\n}\nsubscription {\n}\n",
                'system': 'password_auth: true\nallow_anonymous_loopback: false\n',
                'database': base64.b64encode(gzip.compress((root / 'state.db').read_bytes())).decode(),
            }
            module.prepare(bundle, root / 'files')
            state = root / 'files/etc/honk/state/honk.db'
            self.assertEqual(state.stat().st_mode & 0o777, 0o600)
            with sqlite3.connect(state) as db:
                self.assertEqual(db.execute('SELECT count(*) FROM admin').fetchone()[0], 1)
                self.assertEqual(db.execute('SELECT count(*) FROM subscription_body').fetchone()[0], 1)
                self.assertEqual(db.execute('SELECT count(*) FROM dns_answer').fetchone()[0], 0)
            bundle['system'] = 'password_auth: false'
            with self.assertRaises(ValueError):
                module.prepare(bundle, root / 'rejected')
            bundle['system'] = 'password_auth: true\nallow_anonymous_loopback: false'
            bundle['database'] = base64.b64encode(gzip.compress(b'broken SQLite')).decode()
            with self.assertRaises(sqlite3.DatabaseError):
                module.prepare(bundle, root / 'rejected')


if __name__ == '__main__':
    unittest.main()
