#!/bin/bash
set -e
mkdir -p /logs/verifier

ROUTER_BACKUP=$(mktemp)
cp -a /home/user/router_cli "$ROUTER_BACKUP"
restore_router() {
    cp -a "$ROUTER_BACKUP" /home/user/router_cli
    rm -f "$ROUTER_BACKUP"
}
trap restore_router EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import py_compile
import secrets
import subprocess
from pathlib import Path

SCRIPT_PATH = Path("/home/user/dashboard_updater.py")
JSON_PATH = Path("/home/user/dashboard.json")
ROUTER_PATH = Path("/home/user/router_cli")
LOG_PATH = Path("/tmp/router_verifier_session.log")


def install_router(rx, tx, drops):
    source = f'''#!/usr/bin/env python3
import sys

LOG_PATH = {str(LOG_PATH)!r}

def log(state, command):
    with open(LOG_PATH, "a", encoding="utf-8") as f:
        f.write(state + "|" + command + "\\n")

def main():
    sys.stdout.write("Password: ")
    sys.stdout.flush()
    pw = sys.stdin.readline().strip()
    log("password", pw)
    if pw != "adminpass":
        print("Access denied")
        return

    state = "normal"
    configured = False
    while True:
        prompts = {{
            "normal": "Router> ",
            "enable": "Router# ",
            "config": "Router(config)# ",
            "config-if": "Router(config-if)# ",
        }}
        sys.stdout.write(prompts[state])
        sys.stdout.flush()
        line = sys.stdin.readline()
        if not line:
            break
        cmd = line.strip()
        log(state, cmd)

        if cmd == "enable" and state == "normal":
            state = "enable"
        elif cmd == "configure terminal" and state == "enable":
            state = "config"
        elif cmd == "interface tun0" and state == "config":
            state = "config-if"
        elif cmd == "ip address 10.0.0.1 255.255.255.0" and state == "config-if":
            configured = True
        elif cmd == "exit":
            if state == "config-if":
                state = "config"
            elif state == "config":
                state = "enable"
            elif state == "enable":
                state = "normal"
            else:
                break
        elif cmd == "show interface tun0 metrics" and state in ("normal", "enable"):
            if not configured:
                print("Interface tun0 is not configured.")
            else:
                print("Interface tun0:")
                print(" Rx_Bytes: {rx}")
                print(" Tx_Bytes: {tx}")
                print(" Drops: {drops}")
        elif cmd == "quit":
            break
        elif cmd:
            print(f"Unknown command: {{cmd}}")

if __name__ == "__main__":
    main()
'''
    ROUTER_PATH.write_text(source, encoding="utf-8")
    os.chmod(ROUTER_PATH, 0o755)


def assert_required_interaction():
    assert LOG_PATH.is_file(), "The router CLI was not started."
    entries = LOG_PATH.read_text(encoding="utf-8").splitlines()
    assert entries and entries[0] == "password|adminpass", "The script did not authenticate with the router CLI."

    commands = [entry.split("|", 1)[1] for entry in entries if "|" in entry]
    required = [
        "adminpass",
        "enable",
        "configure terminal",
        "interface tun0",
        "ip address 10.0.0.1 255.255.255.0",
        "exit",
        "exit",
        "show interface tun0 metrics",
    ]
    position = 0
    for command in commands:
        if position < len(required) and command == required[position]:
            position += 1
    assert position == len(required), "The required router configuration and metrics commands were not sent in order."


def run_updater(rx, tx, drops):
    install_router(rx, tx, drops)
    LOG_PATH.write_text("", encoding="utf-8")
    os.chmod(LOG_PATH, 0o666)
    if JSON_PATH.exists() or JSON_PATH.is_symlink():
        JSON_PATH.unlink()

    result = subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user", "python3", str(SCRIPT_PATH)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f"dashboard_updater.py failed:\n{result.stdout}\n{result.stderr}"
    assert JSON_PATH.is_file(), "Running dashboard_updater.py did not generate dashboard.json."
    assert_required_interaction()
    with JSON_PATH.open("r", encoding="utf-8") as f:
        return json.load(f)


def test_01_script_executes_router_and_parses_unexpected_metrics():
    assert SCRIPT_PATH.exists(), f"Expected file {SCRIPT_PATH} does not exist."
    assert SCRIPT_PATH.is_file(), f"Expected {SCRIPT_PATH} to be a file."
    py_compile.compile(str(SCRIPT_PATH), doraise=True)

    rx = 200000 + secrets.randbelow(700000)
    tx = 300000 + secrets.randbelow(600000)
    drops = 100 + secrets.randbelow(900)
    data = run_updater(rx, tx, drops)

    assert data == {
        "panels": [
            {
                "title": "tun0 Traffic",
                "metrics": {
                    "rx_bytes": rx,
                    "tx_bytes": tx,
                    "drops": drops,
                },
            }
        ]
    }


def test_02_dashboard_json_exists_and_correct():
    run_updater(154321, 89432, 12)
    json_path = "/home/user/dashboard.json"

    assert os.path.exists(json_path), f"Expected file {json_path} does not exist."
    assert os.path.isfile(json_path), f"Expected {json_path} to be a file."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {json_path} does not contain valid JSON."

    assert "panels" in data, "JSON missing 'panels' key."
    assert isinstance(data["panels"], list), "'panels' must be a list."
    assert len(data["panels"]) > 0, "'panels' list is empty."

    panel = data["panels"][0]
    assert panel.get("title") == "tun0 Traffic", "Panel title is not 'tun0 Traffic'."

    assert "metrics" in panel, "Panel missing 'metrics' key."
    metrics = panel["metrics"]

    assert metrics.get("rx_bytes") == 154321, f"Expected rx_bytes to be 154321, got {metrics.get('rx_bytes')}."
    assert metrics.get("tx_bytes") == 89432, f"Expected tx_bytes to be 89432, got {metrics.get('tx_bytes')}."
    assert metrics.get("drops") == 12, f"Expected drops to be 12, got {metrics.get('drops')}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
