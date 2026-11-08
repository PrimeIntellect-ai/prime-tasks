#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import struct
import subprocess

PROJECT = "/home/user/packet_parser"


def test_project_builds_runs_and_generates_dump():
    source_path = os.path.join(PROJECT, "src", "main.rs")
    capture_path = os.path.join(PROJECT, "capture.dat")
    dump_path = os.path.join(PROJECT, "crash_dump.bin")

    assert os.path.isfile(source_path), f"The Rust source file {source_path} does not exist."
    assert os.path.isfile(capture_path), f"The capture file {capture_path} does not exist."

    subprocess.run(
        ["cargo", "clean"], cwd=PROJECT, check=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60
    )
    build = subprocess.run(
        ["cargo", "build"], cwd=PROJECT,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120
    )
    assert build.returncode == 0, f"cargo build failed:\n{build.stdout}"

    if os.path.lexists(dump_path):
        os.unlink(dump_path)

    run = subprocess.run(
        ["cargo", "run"], cwd=PROJECT,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120
    )
    assert run.returncode != 0, "cargo run was expected to panic on the malformed packet."
    assert os.path.isfile(dump_path), f"cargo run did not generate {dump_path}."
    assert not os.path.islink(dump_path), f"{dump_path} must be a generated regular file, not a symlink."

    malformed = []
    with open(capture_path, "rb") as f:
        assert f.read(4) == b"PCAP", "capture.dat has an invalid header."
        while True:
            seq_bytes = f.read(2)
            if not seq_bytes:
                break
            assert len(seq_bytes) == 2, "capture.dat has a truncated sequence number."
            len_bytes = f.read(2)
            assert len(len_bytes) == 2, "capture.dat has a truncated payload length."
            seq = struct.unpack(">H", seq_bytes)[0]
            length = struct.unpack(">H", len_bytes)[0]
            payload = f.read(length)
            assert len(payload) == length, "capture.dat has a truncated payload."
            if b"MALFORMED" in payload:
                malformed.append((seq, payload))

    assert len(malformed) == 1, "Expected exactly one malformed packet in capture.dat."
    seq, payload = malformed[0]
    expected_error = f"FATAL_ERR_SEQ_{seq}".encode("ascii")

    with open(dump_path, "rb") as f:
        dump = f.read()
    assert expected_error in dump, "The generated crash dump lacks the expected fatal error code."
    assert payload in dump, "The generated crash dump lacks the malformed packet payload."


def test_debug_report_exists_and_correct():
    report_path = "/home/user/debug_report.txt"
    assert os.path.isfile(report_path), f"The file {report_path} does not exist."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 non-empty lines in {report_path}, found {len(lines)}."
    assert lines[0] == "42", f"Expected sequence number '42' on line 1, found '{lines[0]}'."
    assert lines[1] == "MALFORMED_DATA_FRAG", f"Expected payload 'MALFORMED_DATA_FRAG' on line 2, found '{lines[1]}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
