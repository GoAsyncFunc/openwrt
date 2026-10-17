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
 option ipv6_enable '0'
 option ipv6_dns '0'
 option ipv6_mode '1'
 option enable_v6_udp_proxy '0'
 option china_ip6_route '1'
 option redirect_dns '1'
 option cn_key 'example-dashboard-secret'
config config_subscribe
 option name 'GPT'
 option address 'https://other.example.test/private'
config config_subscribe
 option name 'kitty.fo'
 option address 'https://subscription.example.test/private'
 option sub_convert '0'
""",
            "profile": yaml.safe_dump({
                "mode": "global", "proxies": [{"name": "test", "type": "direct"}],
                "proxy-groups": [{"name": "select", "type": "select", "proxies": ["DIRECT", "test"]}],
                "rules": ["MATCH,select"],
            }),
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
                               "ipv6_enable": "1", "ipv6_dns": "1", "ipv6_mode": "0",
                               "enable_v6_udp_proxy": "1", "china_ip6_route": "0",
                               "config_update_week_time": "*", "auto_update_time": "4"}.items():
                self.assertEqual(prepare.option(settings, key), value)
            self.assertNotIn("other.example.test", text)
            self.assertNotIn("GPT", text)
            self.assertEqual(prepare.option(settings, "config_path"), "/etc/openclash/config/kitty.fo.yaml")
            self.assertEqual(len([s for s in sections if s[0] == "config_subscribe"]), 1)
            self.assertEqual(prepare.option(sections[-1], "sub_ua"), "clash-verge/v2.4.5")
            self.assertEqual(config.stat().st_mode & 0o777, 0o600)
            profile = root / "etc/openclash/config/kitty.fo.yaml"
            self.assertEqual(profile.read_text(), bundle["profile"])
            self.assertEqual(profile.stat().st_mode & 0o777, 0o600)
            self.assertTrue((root / "etc/uci-defaults/98-r66s-personal-openclash").stat().st_mode & 0o100)
            bundle["profile"] = "proxies: []"
            with self.assertRaises(ValueError):
                prepare.prepare(bundle, root)

    def test_provider_scalar_spelling_is_preserved(self):
        profile = """mode: rule
proxies:
  - name: example
    type: vless
    reality-opts:
      short-id: 01234567
proxy-groups:
  - name: choose
    type: select
    proxies: [example]
rules: ['MATCH,choose']
"""
        uci = """config openclash 'config'
config config_subscribe
 option name 'kitty.fo'
 option address 'https://subscription.example.test/private'
 option sub_convert '0'
"""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            prepare.prepare({"uci": uci, "profile": profile}, root)
            self.assertEqual((root / "etc/openclash/config/kitty.fo.yaml").read_text(), profile)


if __name__ == "__main__":
    unittest.main()
