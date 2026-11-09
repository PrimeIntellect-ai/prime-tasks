#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
import pytest


def golden_for_file(path):
    golden_lines = []
    with open(path, "rb") as f:
        while True:
            hdr = f.read(14)
            if not hdr:
                break
            assert len(hdr) == 14, "Incomplete record header in generated test data."
            _ts, ev_type, plen = struct.unpack("<QIH", hdr)
            record_path = f.read(plen)
            assert len(record_path) == plen, "Incomplete path in generated test data."
            if ev_type == 3 and record_path.endswith(b".conf"):
                golden_lines.append(record_path)

    output = b"\n".join(golden_lines)
    if golden_lines:
        output += b"\n"
    return output


def run_filter(input_path):
    try:
        return subprocess.run(
            ["/home/user/fast_filter", input_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("/home/user/fast_filter did not finish within the verification timeout.")


def test_00_required_files_and_build_script():
    assert os.path.isfile("/home/user/fast_filter.c"), "/home/user/fast_filter.c is missing."
    assert os.path.isfile("/home/user/build_and_test.sh"), "/home/user/build_and_test.sh is missing."
    assert os.access("/home/user/build_and_test.sh", os.X_OK), "/home/user/build_and_test.sh is not executable."

    assert os.path.isfile("/home/user/fast_filter"), "Compiled binary /home/user/fast_filter is missing."
    assert os.access("/home/user/fast_filter", os.X_OK), "/home/user/fast_filter is not executable."
    assert os.path.isfile("/home/user/filtered.log"), "Output file /home/user/filtered.log is missing."

    # Force the submitted build script to recreate its required artifacts.
    os.unlink("/home/user/fast_filter")
    os.unlink("/home/user/filtered.log")
    try:
        result = subprocess.run(
            ["/home/user/build_and_test.sh"],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("build_and_test.sh did not finish within the verification timeout.")

    assert result.returncode == 0, (
        "build_and_test.sh failed: " + result.stderr.decode(errors="ignore")
    )
    assert os.path.isfile("/home/user/fast_filter"), "build_and_test.sh did not create /home/user/fast_filter."
    assert os.access("/home/user/fast_filter", os.X_OK), "The rebuilt fast_filter is not executable."
    with open("/home/user/fast_filter", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/fast_filter is not a compiled ELF executable."

    assert os.path.isfile("/home/user/test_events.bin"), "build_and_test.sh did not generate test_events.bin."
    assert os.path.isfile("/home/user/filtered.log"), "build_and_test.sh did not produce filtered.log."
    with open("/home/user/filtered.log", "rb") as f:
        actual = f.read()
    assert actual == golden_for_file("/home/user/test_events.bin"), (
        "filtered.log does not contain the correct output for test_events.bin."
    )


def test_fast_filter_on_unpredictable_records():
    test_path = f"/tmp/custom_events_{secrets.token_hex(12)}.bin"
    expected = []
    suffixes = [b".conf", b".conf.bak", b".CONF", b"conf", b".config", b""]

    with open(test_path, "wb") as f:
        for i in range(257):
            ev_type = secrets.randbelow(5) + 1
            suffix = suffixes[secrets.randbelow(len(suffixes))]
            record_path = b"/verify/" + secrets.token_hex(10).encode() + suffix
            # Guarantee both positive and negative boundary cases.
            if i == 0:
                ev_type, record_path = 3, b"/verify/exact.conf"
            elif i == 1:
                ev_type, record_path = 2, b"/verify/wrong_event.conf"
            elif i == 2:
                ev_type, record_path = 3, b"/verify/not.conf.extra"
            timestamp = secrets.randbits(64)
            f.write(struct.pack("<QIH", timestamp, ev_type, len(record_path)))
            f.write(record_path)
            if ev_type == 3 and record_path.endswith(b".conf"):
                expected.append(record_path)

    expected_output = b"\n".join(expected) + (b"\n" if expected else b"")
    result = run_filter(test_path)
    assert result.returncode == 0, (
        "Agent binary crashed or returned non-zero. Stderr: "
        + result.stderr.decode(errors="ignore")
    )
    assert result.stdout == expected_output, (
        "fast_filter produced incorrect output for independently generated records."
    )


def test_fast_filter_correctness_on_large_random_seed():
    seed = str(secrets.randbelow(2_000_000_000) + 1)
    eval_bin = f"/tmp/eval_events_{secrets.token_hex(12)}.bin"

    try:
        generated = subprocess.run(
            ["/app/bin/fs_event_gen", seed, eval_bin],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("fs_event_gen did not finish within the verification timeout.")

    assert generated.returncode == 0, (
        "Failed to generate verification data: " + generated.stderr.decode(errors="ignore")
    )
    assert os.path.exists(eval_bin), f"Test data file {eval_bin} was not created."

    result = run_filter(eval_bin)
    assert result.returncode == 0, (
        "Agent binary crashed or returned non-zero. Stderr: "
        + result.stderr.decode(errors="ignore")
    )
    assert result.stdout == golden_for_file(eval_bin), (
        "Output from /home/user/fast_filter does not match the expected filtered data."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
