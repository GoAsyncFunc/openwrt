#!/usr/bin/env python3
"""Create a private build overlay from JSON on stdin; never print its contents."""

import json
import os
from pathlib import Path
import shlex
import sys

import yaml


def parse_uci(text):
    sections = []
    pending = ""
    for line in text.splitlines(keepends=True):
        pending += line
        try:
            row = shlex.split(pending, comments=True)
        except ValueError:
            continue  # UCI permits quoted values spanning multiple lines.
        pending = ""
        if not row:
            continue
        if row[0] == "config" and len(row) in (2, 3):
            sections.append([row[1], row[2] if len(row) == 3 else None, []])
        elif row[0] in ("option", "list") and len(row) == 3 and sections:
            sections[-1][2].append(row)
        else:
            raise ValueError("Invalid UCI input")
    if pending:
        raise ValueError("Unterminated UCI input")
    return sections


def option(section, key):
    return next((v for _, k, v in section[2] if k == key), None)


def set_option(section, key, value):
    section[2][:] = [row for row in section[2] if row[1] != key]
    section[2].append(["option", key, value])


def write_private(path, content, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    path.chmod(mode)


def prepare(bundle, overlay):
    profile = yaml.safe_load(bundle["profile"])
    # A nodes-only subscription or a remote provider is insufficient at first boot.
    if not isinstance(profile, dict) or not all(
        isinstance(profile.get(key), list) and profile[key]
        for key in ("proxies", "proxy-groups", "rules")
    ) or profile.get("proxy-providers"):
        raise ValueError("A complete, self-contained Clash profile is required")
    sections = parse_uci(bundle["uci"])
    global_config = next(s for s in sections if s[:2] == ["openclash", "config"])
    subscription = next(
        s for s in sections
        if s[0] == "config_subscribe" and option(s, "name") == "kitty.fo"
    )
    if not (option(subscription, "address") or "").startswith("https://"):
        raise ValueError("Missing HTTPS subscription")
    if option(subscription, "sub_convert") != "0":
        raise ValueError("Subscription conversion must be resolved before bundling")
    # Exclude other subscriptions and state saved while hijacking the running DNS.
    sections = [s for s in sections if s[0] in ("openclash", "dns_servers", "authentication")]
    sections.append(subscription)
    for key, value in {
        "enable": "1", "config_path": "/etc/openclash/config/kitty.fo.yaml",
        "en_mode": "redir-host-mix", "operation_mode": "redir-host",
        "proxy_mode": "rule", "auto_update": "1",
        "config_auto_update_mode": "0", "config_update_week_time": "*",
        "auto_update_time": "4", "delay_start": "10",
        "redirect_dns": "0", "cachesize_dns": "0", "filter_aaaa_dns": "0",
        "update": "0",
    }.items():
        set_option(global_config, key, value)
    set_option(subscription, "enabled", "1")
    set_option(subscription, "sub_ua", "clash-verge/v2.4.5")
    lines = []
    for kind, name, rows in sections:
        lines.append("config " + shlex.quote(kind) + (" " + shlex.quote(name) if name else ""))
        lines.extend("\t" + command + " " + shlex.quote(key) + " " + shlex.quote(value)
                     for command, key, value in rows)
        lines.append("")
    write_private(overlay / "etc/config/openclash", "\n".join(lines))
    # Preserve the provider's scalar spelling (notably Reality identifiers).
    # OpenClash applies rule/mixed mode from UCI when producing its runtime YAML.
    write_private(overlay / "etc/openclash/config/kitty.fo.yaml", bundle["profile"])
    write_private(overlay / "etc/uci-defaults/98-r66s-personal-openclash",
                  "#!/bin/sh\n/etc/init.d/cron enable\n/etc/init.d/openclash enable\nexit 0\n",
                  0o700)


if __name__ == "__main__":
    os.umask(0o077)
    try:
        prepare(json.load(sys.stdin), Path(sys.argv[1] if len(sys.argv) > 1 else "files"))
    except Exception:
        # Parser exceptions can contain subscription credentials or YAML node values.
        sys.exit("Private OpenClash input is invalid; details suppressed")
    print("Private OpenClash overlay prepared (contents suppressed)")
