#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
from pathlib import Path

from scapy.all import UDP, Raw, rdpcap

WORKSPACE = Path("/home/user/diagnostic_workspace")
PROJECT = WORKSPACE / "pcap_ingest"
REPORT = Path("/home/user/report.txt")
TARGET = Path("/tmp/verifier-pcap-ingest-target")


def expected_report():
    packets = rdpcap(str(WORKSPACE / "capture.pcap"))
    for number, packet in enumerate(packets, start=1):
        if UDP not in packet:
            continue
        payload = bytes(packet[UDP].payload)
        if not payload:
            continue
        try:
            json.loads(payload)
        except (UnicodeDecodeError, json.JSONDecodeError):
            return f"Packet: {number}\nPayload: {payload.hex()}"
    raise AssertionError("capture.pcap contains no malformed UDP JSON payload")


def test_report_exists():
    assert REPORT.is_file(), f"Report file {REPORT} does not exist. Did you create it?"


def test_report_content():
    assert REPORT.is_file(), f"Report file {REPORT} does not exist."
    content = REPORT.read_text().strip()
    expected_content = expected_report()
    assert content == expected_content, (
        f"The content of {REPORT} is incorrect.\n"
        f"Expected:\n{expected_content}\nGot:\n{content}"
    )


def test_build_rs_fixed_and_project_builds():
    build_rs_path = PROJECT / "build.rs"
    assert build_rs_path.is_file(), f"build.rs {build_rs_path} is missing."

    lines = build_rs_path.read_text().splitlines()
    search_path_added = any(
        "cargo:rustc-link-search=native=" in line
        and not line.strip().startswith("//")
        for line in lines
    )
    assert search_path_added, (
        "build.rs does not contain an active 'cargo:rustc-link-search' directive. "
        "The build environment was not fixed."
    )

    shutil.rmtree(TARGET, ignore_errors=True)
    env = os.environ.copy()
    env["CARGO_TARGET_DIR"] = str(TARGET)
    result = subprocess.run(
        ["cargo", "build"],
        cwd=PROJECT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=180,
    )
    assert result.returncode == 0, f"cargo build failed:\n{result.stdout}"

    executable = TARGET / "debug" / "pcap_ingest"
    assert executable.is_file(), f"Built service executable is missing: {executable}"
    run = subprocess.run(
        [str(executable)],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=30,
    )
    assert run.returncode != 0, "The diagnostic service did not reproduce the payload crash."
    assert "Serialization error" in run.stdout, (
        f"The service failed for an unexpected reason:\n{run.stdout}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
