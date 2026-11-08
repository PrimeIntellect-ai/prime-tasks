#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from pathlib import Path


def test_script_exists_and_executable():
    script_path = "/home/user/audit_configs.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_csv_exists():
    csv_path = "/home/user/verified_changes.csv"
    assert os.path.isfile(csv_path), f"Output CSV {csv_path} does not exist."


def test_csv_content():
    csv_path = "/home/user/verified_changes.csv"
    assert os.path.isfile(csv_path), f"Output CSV {csv_path} does not exist."

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "Ticket,Filename,Status",
        "TKT-1001,router_v1.bin,Valid",
        "TKT-1001,router_v2.bin,Corrupt",
        "TKT-1002,firewall_v2.bin,Valid",
        "TKT-1002,missing_fw.bin,Missing",
        "TKT-1004,proxy_v1.bin,Corrupt",
        "TKT-1004,switch_v1.bin,Valid"
    ]

    assert len(lines) > 0, "CSV file is empty."
    assert lines[0] == expected_lines[0], f"CSV header is incorrect. Expected '{expected_lines[0]}', got '{lines[0]}'."

    for line in lines:
        assert "TKT-1003" not in line, "Rejected ticket TKT-1003 should not be in the output."

    assert lines == expected_lines, "CSV content does not match the expected output or is not sorted correctly."


def test_script_processes_changed_fixtures():
    home = Path("/home/user")
    backups = home / "config_backups"
    log_path = home / "change_history.log"
    csv_path = home / "verified_changes.csv"
    script_path = home / "audit_configs.sh"

    nonce = secrets.token_hex(6)
    base = 2000 + secrets.randbelow(6000)
    approved_ticket = f"TKT-{base:04d}"
    pending_ticket = f"TKT-{base + 1:04d}"
    rejected_ticket = f"TKT-{base + 2:04d}"

    corrupt_name = f"a_corrupt_{nonce}.bin"
    valid_name = f"z_valid_{nonce}.bin"
    missing_name = f"b_missing_{nonce}.bin"
    exact_valid_name = f"c_exact_valid_{nonce}.bin"
    rejected_name = f"rejected_{nonce}.bin"

    (backups / corrupt_name).write_bytes(b"\xcf\xfa\xed\xfd\x00\x11")
    (backups / valid_name).write_bytes(b"\xcf\xfa\xed\xfe\x00\xff\x10\x20")
    (backups / exact_valid_name).write_bytes(b"\xcf\xfa\xed\xfe")
    (backups / rejected_name).write_bytes(b"\xcf\xfa\xed\xfe\xaa")
    missing_path = backups / missing_name
    if missing_path.exists():
        missing_path.unlink()

    log_path.write_text(
        f"Ticket: {approved_ticket}\n"
        "Author: Dynamic One\n"
        "Files:\n"
        f" - {valid_name}\n"
        f" - {corrupt_name}\n"
        "Status: Approved\n"
        "---\n"
        f"Ticket: {pending_ticket}\n"
        "Author: Dynamic Two\n"
        "Files:\n"
        f" - {missing_name}\n"
        f" - {exact_valid_name}\n"
        "Status: Pending\n"
        "---\n"
        f"Ticket: {rejected_ticket}\n"
        "Author: Dynamic Three\n"
        "Files:\n"
        f" - {rejected_name}\n"
        "Status: Rejected\n"
        "---\n"
    )

    if csv_path.exists():
        csv_path.unlink()

    subprocess.run(
        [str(script_path)],
        cwd=str(home),
        check=True,
        timeout=10,
    )

    assert csv_path.is_file(), "The script did not recreate verified_changes.csv."
    with csv_path.open("r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "Ticket,Filename,Status",
        f"{approved_ticket},{corrupt_name},Corrupt",
        f"{approved_ticket},{valid_name},Valid",
        f"{pending_ticket},{missing_name},Missing",
        f"{pending_ticket},{exact_valid_name},Valid",
    ]

    assert all(rejected_ticket not in line for line in lines), "Rejected ticket was included in dynamic output."
    assert lines == expected_lines, "Script did not correctly parse and validate the changed fixtures."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
