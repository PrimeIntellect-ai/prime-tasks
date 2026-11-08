#!/bin/bash
set -e
mkdir -p /logs/verifier

BACKUP_DIR="$(mktemp -d)"
cp -a /home/user/config_changes.csv "$BACKUP_DIR/config_changes.csv"
if [ -f /home/user/hourly_report.md ]; then
    cp -a /home/user/hourly_report.md "$BACKUP_DIR/hourly_report.md"
    touch "$BACKUP_DIR/report_existed"
fi
restore_files() {
    cp -a "$BACKUP_DIR/config_changes.csv" /home/user/config_changes.csv
    if [ -f "$BACKUP_DIR/report_existed" ]; then
        cp -a "$BACKUP_DIR/hourly_report.md" /home/user/hourly_report.md
    else
        rm -f /home/user/hourly_report.md
    fi
    rm -rf "$BACKUP_DIR"
}
trap restore_files EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest


def test_rust_project_exists():
    """Verify that the Rust project was created."""
    project_dir = "/home/user/config_tracker"
    cargo_toml = os.path.join(project_dir, "Cargo.toml")

    assert os.path.isdir(project_dir), f"Rust project directory {project_dir} is missing."
    assert os.path.isfile(cargo_toml), f"Cargo.toml is missing in {project_dir}. Did you create a Rust project?"


def test_markdown_report_exists():
    """Verify that the output Markdown report exists."""
    report_path = "/home/user/hourly_report.md"
    assert os.path.isfile(report_path), f"Output report {report_path} is missing."


def test_markdown_report_content():
    """Verify that the output Markdown report has the exact expected content."""
    report_path = "/home/user/hourly_report.md"

    if not os.path.isfile(report_path):
        pytest.fail(f"Output report {report_path} is missing, cannot check content.")

    expected_content = (
        "# Configuration Change Report\n"
        "\n"
        "## Hour: 2023-10-01T10\n"
        "- srvA: max_conn (2)\n"
        "- srvB: motd (1)\n"
        "\n"
        "## Hour: 2023-10-01T11\n"
        "- srvA: timeout (2)\n"
        "\n"
        "## Hour: 2023-10-02T09\n"
        "- srvB: max_conn (1)\n"
        "- srvC: log_level (1)\n"
    )

    with open(report_path, "r", encoding="utf-8") as f:
        actual_content = f.read()

    assert actual_content == expected_content, (
        "The content of the Markdown report does not match the expected output. "
        "Check formatting, sorting, and aggregation logic."
    )
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_execution.py
import csv
import os
import secrets
import subprocess
from collections import Counter

PROJECT = "/home/user/config_tracker"
INPUT = "/home/user/config_changes.csv"
REPORT = "/home/user/hourly_report.md"


def expected_report(rows):
    counts = Counter((timestamp[:13], server_id, config_key)
                     for timestamp, server_id, config_key, _ in rows)
    lines = ["# Configuration Change Report"]
    hours = sorted({hour for hour, _, _ in counts})
    for hour in hours:
        lines.extend(["", f"## Hour: {hour}"])
        servers = sorted({server for h, server, _ in counts if h == hour})
        for server in servers:
            keys = sorted(key for h, s, key in counts if h == hour and s == server)
            for key in keys:
                lines.append(f"- {server}: {key} ({counts[(hour, server, key)]})")
    return "\n".join(lines) + "\n"


def run_case(rows):
    with open(INPUT, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["timestamp", "server_id", "config_key", "config_value"])
        writer.writerows(rows)

    if os.path.exists(REPORT):
        os.remove(REPORT)

    result = subprocess.run(
        ["cargo", "run", "--quiet", "--offline", "--manifest-path", os.path.join(PROJECT, "Cargo.toml")],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"cargo run failed with exit status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT), "Running the Rust project did not create hourly_report.md"
    with open(REPORT, "r", encoding="utf-8") as f:
        actual = f.read()
    assert actual == expected_report(rows), (
        "The report produced by executing the Rust project did not correctly parse, "
        "sort, format, and aggregate the verification CSV."
    )


def main():
    rust_sources = []
    for root, _, files in os.walk(PROJECT):
        rust_sources.extend(os.path.join(root, name) for name in files if name.endswith(".rs"))
    assert rust_sources, "The Cargo project contains no Rust source files"
    assert any(os.path.getsize(path) > 0 for path in rust_sources), "The Rust source files are empty"

    token = secrets.token_hex(5)
    rows_one = [
        ("2024-03-02T12:59:59Z", f"zeta_{token}", f"workers_{token}", "first line\nsecond line"),
        ("2024-03-02T07:03:00Z", f"beta_{token}", f"motd_{token}", "hello, world\nnext line"),
        ("2024-03-02T12:01:00Z", f"alpha_{token}", f"timeout_{token}", "30"),
        ("2024-03-02T07:45:00Z", f"beta_{token}", f"motd_{token}", "changed\nagain"),
        ("2024-03-02T12:02:00Z", f"alpha_{token}", f"cache_{token}", "on"),
        ("2024-03-01T23:58:00Z", f"gamma_{token}", f"level_{token}", "DEBUG\nVERBOSE"),
        ("2024-03-02T12:03:00Z", f"alpha_{token}", f"timeout_{token}", "40"),
        ("2024-03-02T07:46:00Z", f"alpha_{token}", f"workers_{token}", "value with \"quotes\"\nand a comma, too"),
    ]
    run_case(rows_one)

    rows_two = [
        ("2025-11-10T09:15:00Z", f"node_b_{token}", f"mode_{token}", "safe\nmultiline"),
        ("2025-11-10T08:59:00Z", f"node_c_{token}", f"port_{token}", "8080"),
        ("2025-11-10T09:16:00Z", f"node_b_{token}", f"mode_{token}", "fast"),
        ("2025-11-10T09:17:00Z", f"node_b_{token}", f"mode_{token}", "fastest\nstill one CSV record"),
        ("2025-11-10T09:01:00Z", f"node_a_{token}", f"zone_{token}", "west"),
        ("2025-11-10T08:01:00Z", f"node_c_{token}", f"port_{token}", "9090\nbackup"),
    ]
    run_case(rows_two)


if __name__ == "__main__":
    main()
DYNAMIC_EOF

run_all_tests() {
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 &&
    python3 /tmp/test_dynamic_execution.py 2>&1
}

if run_all_tests; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
