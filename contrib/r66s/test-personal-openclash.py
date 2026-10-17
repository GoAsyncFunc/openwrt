#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
import unittest

import yaml

spec = importlib.util.spec_from_file_location(
    "prepare", Path(__file__).with_name("prepare-personal-openclash.py"))
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class PersonalOverlayTests(unittest.TestCase):
    def test_private_profile_and_only_selected_subscription(self):
        bundle = {
            "uci": """config openclash 'config'
 option enable '0'
 option redirect_dns '1'
 option cn_key 'example-dashboard-secret'
config config_subscribe
 option name 'other'
 option address 'https://other.example.test/private'
config config_subscribe
 option name 'GPT'
 option address 'https://subscription.example.test/private'
 option sub_convert '0'
""",
            "profile": yaml.safe_dump({
                "mode": "global", "proxies": [{"name": "test", "type": "direct"}],
                "proxy-groups": [{"name": "select", "type": "select", "proxies": ["DIRECT", "test"]}],
                "rules": ["MATCH,select"],
            }),
            "selections": {"select": "test"},
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prepare.prepare(bundle, root)
            config = root / "etc/config/openclash"
            text = config.read_text()
            sections = prepare.parse_uci(text)
            settings = sections[0]
            for key, value in {"enable": "1", "auto_update": "1", "proxy_mode": "rule",
                               "en_mode": "redir-host-mix", "redirect_dns": "0",
                               "config_update_week_time": "*", "auto_update_time": "4"}.items():
                self.assertEqual(prepare.option(settings, key), value)
            self.assertNotIn("other.example.test", text)
            self.assertEqual(len([s for s in sections if s[0] == "config_subscribe"]), 1)
            self.assertEqual(config.stat().st_mode & 0o777, 0o600)
            profile = root / "etc/openclash/config/GPT.yaml"
            self.assertEqual(yaml.safe_load(profile.read_text())["mode"], "rule")
            self.assertEqual(yaml.safe_load(profile.read_text())["proxy-groups"][0]["proxies"][0], "test")
            self.assertEqual(profile.stat().st_mode & 0o777, 0o600)
            self.assertTrue((root / "etc/uci-defaults/98-r66s-personal-openclash").stat().st_mode & 0o100)
            bundle["profile"] = "proxies: []"
            with self.assertRaises(ValueError):
                prepare.prepare(bundle, root)


if __name__ == "__main__":
    unittest.main()
