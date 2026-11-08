#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import struct
import subprocess

import pytest

PROJ_DIR = "/home/user/sec_analyzer"
BINARY = os.path.join(PROJ_DIR, "target", "debug", "sec_analyzer")


def run_analyzer(trace_path, timeout=20):
    result = subprocess.run(
        [BINARY, trace_path],
        cwd=PROJ_DIR,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    assert result.returncode == 0, (
        f"analyzer failed for {trace_path} with code {result.returncode}:\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    matches = re.findall(r"^Total packets processed: ([0-9]+)$", result.stdout, re.MULTILINE)
    assert len(matches) == 1, f"expected exactly one packet total, got stdout: {result.stdout!r}"
    return int(matches[0])


def test_minimal_trigger_bin():
    path = "/home/user/minimal_trigger.bin"
    assert os.path.isfile(path), f"File {path} does not exist"
    with open(path, "rb") as f:
        data = f.read()
    assert data == b"\x02\x00\xff\xff", f"minimal_trigger.bin content is incorrect: {data.hex()}"


def test_report_txt():
    path = "/home/user/report.txt"
    assert os.path.isfile(path), f"File {path} does not exist"
    with open(path, "r") as f:
        raw_lines = f.read().splitlines()
    assert raw_lines == ["24", "sec_analyzer::parser::parse_packet"], (
        f"report.txt must contain exactly the two requested lines, got: {raw_lines!r}"
    )
    lines = [line.strip() for line in raw_lines if line.strip()]
    assert len(lines) >= 2, "report.txt must contain at least two lines"
    assert lines[1] == "sec_analyzer::parser::parse_packet", f"Line 2 of report.txt is incorrect: {lines[1]}"
    assert lines[0].isdigit(), f"Line 1 of report.txt should be a line number, got: {lines[0]}"


def test_processor_uses_atomic():
    path = os.path.join(PROJ_DIR, "src", "processor.rs")
    assert os.path.isfile(path), f"File {path} does not exist"
    with open(path, "r") as f:
        content = f.read()
    assert "AtomicUsize" in content, "processor.rs does not use AtomicUsize to fix the race condition"
    code_without_comments = re.sub(r"//.*?$|/\*.*?\*/", "", content, flags=re.MULTILINE | re.DOTALL)
    assert "static mut" not in code_without_comments, "processor.rs still uses an unsafe mutable global counter"


def test_parser_fixed():
    path = os.path.join(PROJ_DIR, "src", "parser.rs")
    assert os.path.isfile(path), f"File {path} does not exist"
    with open(path, "r") as f:
        content = f.read()
    assert "read_volatile" not in content or "0x1000000000" not in content, (
        "parser.rs still contains the malicious out-of-bounds read"
    )


def test_cargo_build_and_run():
    clean_res = subprocess.run(["cargo", "clean"], cwd=PROJ_DIR, capture_output=True, text=True)
    assert clean_res.returncode == 0, f"cargo clean failed:\n{clean_res.stderr}"

    build_res = subprocess.run(["cargo", "build"], cwd=PROJ_DIR, capture_output=True, text=True)
    assert build_res.returncode == 0, f"cargo build failed:\n{build_res.stderr}"
    build_output = build_res.stdout + "\n" + build_res.stderr
    assert re.search(r"(^|\n)warning:", build_output, re.IGNORECASE) is None, (
        f"cargo build produced warnings:\n{build_output}"
    )
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "cargo did not produce an executable analyzer"

    run_res = subprocess.run(
        ["cargo", "run", "--", "/home/user/trace.bin"],
        cwd=PROJ_DIR,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert run_res.returncode == 0, f"cargo run failed or crashed:\n{run_res.stderr}"
    matches = re.findall(r"^Total packets processed: ([0-9]+)$", run_res.stdout, re.MULTILINE)
    assert matches == ["999"], f"incorrect statistics for trace.bin: {run_res.stdout!r}"


def test_safe_parsing_and_derived_statistics(tmp_path):
    # Build four equal-sized chunks so the program's four worker boundaries are known.
    # Packet payloads and counts are selected at verification time, and each chunk ends
    # with a malformed 0xffff-length packet that must stop parsing without crashing.
    target_size = 32768
    chunks = []
    expected = 0
    for chunk_index in range(4):
        chunk = bytearray()
        while target_size - len(chunk) >= 4 + 31 + 4:
            payload_len = 1 + secrets.randbelow(31)
            packet_id = secrets.randbelow(65536)
            payload = secrets.token_bytes(payload_len)
            chunk += struct.pack("<HH", packet_id, payload_len) + payload
            expected += 1
        remaining = target_size - len(chunk)
        assert remaining >= 4
        chunk += struct.pack("<HH", 0xA000 + chunk_index, 0xFFFF)
        chunk += secrets.token_bytes(remaining - 4)
        assert len(chunk) == target_size
        chunks.append(bytes(chunk))

    trace = tmp_path / "random_malformed_trace.bin"
    trace.write_bytes(b"".join(chunks))
    assert run_analyzer(str(trace)) == expected


def test_atomic_counter_under_load(tmp_path):
    # Every packet is valid and each quarter ends on a packet boundary. Repeated exact
    # totals exercise the shared counter rather than merely checking for a successful exit.
    per_worker = 30000 + secrets.randbelow(5000)
    packet = struct.pack("<HH", secrets.randbelow(65536), 0)
    trace = tmp_path / "counter_stress_trace.bin"
    trace.write_bytes(packet * (per_worker * 4))
    expected = per_worker * 4
    for _ in range(3):
        assert run_analyzer(str(trace), timeout=30) == expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
