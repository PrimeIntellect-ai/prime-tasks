#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import string
import struct
import subprocess
import sys
import tempfile


def test_flag_contents():
    """Test that the flag file contains the correct highest-entropy string."""
    flag_path = "/home/user/flag.txt"
    assert os.path.exists(flag_path), f"Missing file: {flag_path}"
    assert os.path.isfile(flag_path), f"Not a file: {flag_path}"

    with open(flag_path, 'r') as f:
        content = f.read().strip()

    expected_flag = "zQ8#kP9!mB4$vX1&"
    assert content == expected_flag, f"Incorrect flag content. Expected '{expected_flag}', got '{content}'"


def test_candidates_file():
    """Test that the candidates file was generated and contains the valid extracted strings."""
    candidates_path = "/home/user/candidates.txt"
    assert os.path.exists(candidates_path), f"Missing file: {candidates_path}"
    assert os.path.isfile(candidates_path), f"Not a file: {candidates_path}"

    with open(candidates_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_strings = [
        "normal_string_123",
        "debug_log_started",
        "zQ8#kP9!mB4$vX1&"
    ]

    for expected in expected_strings:
        assert expected in lines, f"Missing expected extracted string '{expected}' in {candidates_path}"


def test_flag_is_highest_entropy_candidate():
    """Independently verify that the saved flag is the highest-entropy candidate."""
    with open('/home/user/candidates.txt', 'r') as f:
        candidates = [line.rstrip('\r\n') for line in f if line.rstrip('\r\n')]
    with open('/home/user/flag.txt', 'r') as f:
        flag = f.read().strip()

    def entropy(value):
        return -sum((value.count(ch) / len(value)) * math.log2(value.count(ch) / len(value))
                    for ch in set(value))

    assert candidates, "candidates.txt is empty"
    assert flag == max(candidates, key=entropy), "flag.txt is not the highest-entropy candidate"


def test_extractor_fixed():
    """Execute extractor.py and verify recovery before and after malformed chunks."""
    extractor_path = "/home/user/extractor.py"
    assert os.path.exists(extractor_path), f"Missing file: {extractor_path}"
    assert os.path.isfile(extractor_path), f"Not a file: {extractor_path}"

    candidates_path = "/home/user/candidates.txt"
    old_candidates = open(candidates_path, 'rb').read() if os.path.exists(candidates_path) else None
    token = ''.join(random.SystemRandom().choices(string.ascii_letters + string.digits, k=20))
    expected = ["before_" + token, "after_" + token]

    with tempfile.TemporaryDirectory() as td:
        dump_path = os.path.join(td, 'functional_dump.bin')
        with open(dump_path, 'wb') as f:
            first = expected[0].encode('ascii')
            second = expected[1].encode('ascii')
            f.write(b'CHNK' + struct.pack('<I', len(first)) + first)
            f.write(b'CHNK' + struct.pack('<I', 0xFFFFFFFF) + b'junk-noise')
            f.write(b'CHNK' + struct.pack('<I', len(second)) + second)
            f.write(b'CHNK\x01\x02')  # truncated header

        try:
            if os.path.exists(candidates_path):
                os.unlink(candidates_path)
            result = subprocess.run(
                [sys.executable, extractor_path, dump_path],
                cwd='/home/user', text=True, capture_output=True, timeout=10
            )
            assert result.returncode == 0, f"extractor.py crashed: {result.stderr}"
            assert os.path.isfile(candidates_path), "extractor.py did not generate candidates.txt"
            with open(candidates_path, 'r') as f:
                actual = [line.rstrip('\r\n') for line in f if line.rstrip('\r\n')]
            assert actual == expected, f"Extractor failed malformed-chunk recovery: {actual!r}"
        finally:
            if old_candidates is None:
                if os.path.exists(candidates_path):
                    os.unlink(candidates_path)
            else:
                with open(candidates_path, 'wb') as f:
                    f.write(old_candidates)


def test_analyze_script_functionally_selects_highest_entropy():
    """Execute analyze.py on derived candidates and verify its selected result."""
    analyze_path = "/home/user/analyze.py"
    assert os.path.exists(analyze_path), f"Missing file: {analyze_path}"
    assert os.path.isfile(analyze_path), f"Not a file: {analyze_path}"

    candidates_path = '/home/user/candidates.txt'
    flag_path = '/home/user/flag.txt'
    old_candidates = open(candidates_path, 'rb').read() if os.path.exists(candidates_path) else None
    old_flag = open(flag_path, 'rb').read() if os.path.exists(flag_path) else None

    alphabet = list(string.ascii_letters + string.digits + '!@#$%^&*')
    random.SystemRandom().shuffle(alphabet)
    expected = ''.join(alphabet[:18])
    probe_candidates = ['aaaaaaaaaaaaaaaaaa', 'ababababababababab', expected]

    try:
        with open(candidates_path, 'w') as f:
            for candidate in probe_candidates:
                f.write(candidate + '\n')
        if os.path.exists(flag_path):
            os.unlink(flag_path)

        result = subprocess.run(
            [sys.executable, analyze_path, candidates_path],
            cwd='/home/user', text=True, capture_output=True, timeout=10
        )
        assert result.returncode == 0, f"analyze.py crashed: {result.stderr}"

        produced_flag = None
        if os.path.isfile(flag_path):
            with open(flag_path, 'r') as f:
                produced_flag = f.read().strip()
        reported = result.stdout + result.stderr
        assert produced_flag == expected or expected in reported, (
            "analyze.py did not identify the derived highest-entropy candidate"
        )
    finally:
        if old_candidates is None:
            if os.path.exists(candidates_path):
                os.unlink(candidates_path)
        else:
            with open(candidates_path, 'wb') as f:
                f.write(old_candidates)
        if old_flag is None:
            if os.path.exists(flag_path):
                os.unlink(flag_path)
        else:
            with open(flag_path, 'wb') as f:
                f.write(old_flag)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
