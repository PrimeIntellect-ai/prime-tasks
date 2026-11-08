#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import sys
import tempfile
import pytest


def custom_hash(data: bytes) -> str:
    h = 0x1337BEEF
    for b in data:
        h ^= b
        h = ((h << 3) & 0xFFFFFFFF) | (h >> 29)
    return f"{h:08x}"


def run_analyzer(analyzer_path, input_dir, output_csv, timeout):
    try:
        subprocess.run(
            [sys.executable, analyzer_path, input_dir, output_csv],
            timeout=timeout,
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(
            f"Analyzer script failed with return code {e.returncode}. "
            f"Stderr: {e.stderr}"
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Analyzer script timed out.")


def test_analyzer_script_accuracy():
    analyzer_path = "/home/user/analyzer.py"
    assert os.path.exists(analyzer_path), f"Script {analyzer_path} not found."

    with tempfile.TemporaryDirectory() as tmpdir:
        # Preserve the original fixed cases and their accuracy assertion.
        test_cases = {
            "ok1.html": (b"<html><body><script src='app.js'></script></body></html>", False),
            "ok2.html": (b"<html><script src=\"https://cdn.trusted.com/lib.js\"></script></html>", False),
            "ok3.html": (b"<div>No scripts here</div>", False),
            "ok4.html": (b"<script src='/absolute/path/to/self.js'></script>", False),
            "ok5.html": (b"<script src='./relative/path.js'></script>", False),
            "bad1.html": (b"<html><script>alert(1)</script></html>", True),
            "bad2.html": (b"<script src='https://evil.com/x.js'></script>", True),
            "bad3.html": (b"<body><object data='x.swf'></object></body>", True),
            "bad4.html": (b"<script src=\"http://cdn.trusted.com/lib.js\"></script>", True),
            "bad5.html": (b"<script type='text/javascript'>console.log(1)</script>", True),
            "bad6.html": (b"<script src='//malicious.com/script.js'></script>", True),
            "bad7.html": (b"<OBJECT data='test'></OBJECT>", True),
        }

        expected_csv_lines = []
        for filename, (content, is_violation) in test_cases.items():
            filepath = os.path.join(tmpdir, filename)
            with open(filepath, "wb") as f:
                f.write(content)
            if is_violation:
                expected_csv_lines.append(f"{filename},{custom_hash(content)}")

        expected_csv_lines.sort()

        # Ensure binary is removed to test standalone capability.
        if os.path.exists("/app/auth_tool"):
            os.remove("/app/auth_tool")

        output_csv = os.path.join(tmpdir, "output.csv")
        run_analyzer(analyzer_path, tmpdir, output_csv, 15)

        assert os.path.exists(output_csv), "Output CSV was not created by the script."

        with open(output_csv, "r") as f:
            agent_lines = [line.strip() for line in f if line.strip()]

        gt_set = set(expected_csv_lines)
        agent_set = set(agent_lines)

        if not gt_set:
            accuracy = 0.0
        else:
            correct = len(gt_set.intersection(agent_set))
            total_evaluated = len(gt_set) + max(0, len(agent_set) - len(gt_set))
            accuracy = correct / total_evaluated

        assert accuracy >= 1.0, (
            f"Metric accuracy = {accuracy:.2f} (Threshold >= 1.0). "
            f"Expected {len(gt_set)} correct rows, got {len(agent_set)} rows. "
            f"Missing: {gt_set - agent_set}, Unexpected: {agent_set - gt_set}"
        )

        # Sets alone do not enforce the required ordering or reject duplicates.
        assert agent_lines == expected_csv_lines, (
            "CSV rows must occur exactly once and be alphabetically ordered."
        )


def test_randomized_full_dataset():
    analyzer_path = "/home/user/analyzer.py"
    assert os.path.isfile(analyzer_path), f"Script {analyzer_path} not found."

    if os.path.exists("/app/auth_tool"):
        os.remove("/app/auth_tool")

    with tempfile.TemporaryDirectory() as tmpdir:
        cases = []
        expected = []

        # Generate verification-time filenames and contents so fixed output tables
        # cannot pass. The size matches the 10,000-file evaluation requirement.
        for i in range(10000):
            token = secrets.token_hex(20)
            filename = f"sample_{i:05d}_{secrets.token_hex(5)}.html"
            kind = i % 10

            if kind == 0:
                html = f"<!doctype html><html><body><!--{token}--><p>safe</p></body></html>"
                violation = False
            elif kind == 1:
                html = f"<html><script src='assets/{token}.js'></script></html>"
                violation = False
            elif kind == 2:
                html = f"<script src=\"/{token}/app.js\"></script><!--{token}-->"
                violation = False
            elif kind == 3:
                html = f"<script src='https://cdn.trusted.com/{token}.js'></script>"
                violation = False
            elif kind == 4:
                html = f"<html><script>window.payload='{token}';</script></html>"
                violation = True
            elif kind == 5:
                html = f"<script src='https://evil-{token}.example/x.js'></script>"
                violation = True
            elif kind == 6:
                html = f"<body><object data='{token}.swf'></object></body>"
                violation = True
            elif kind == 7:
                html = f"<SCRIPT type='text/javascript'>console.log('{token}')</SCRIPT>"
                violation = True
            elif kind == 8:
                html = f"<script src='//malicious.example/{token}.js'></script>"
                violation = True
            else:
                html = f"<script src='http://cdn.trusted.com/{token}.js'></script>"
                violation = True

            content = (html + "\n<!-- padding:" + secrets.token_hex(12) + " -->\n").encode("utf-8")
            cases.append((filename, content, violation))
            if violation:
                expected.append(f"{filename},{custom_hash(content)}")

        # Deliberately make directory creation order differ from filename order.
        random.SystemRandom().shuffle(cases)
        for filename, content, _ in cases:
            with open(os.path.join(tmpdir, filename), "wb") as f:
                f.write(content)

        expected.sort()
        output_csv = os.path.join(tmpdir, "result.csv")
        run_analyzer(analyzer_path, tmpdir, output_csv, 45)

        assert os.path.exists(output_csv), "Output CSV was not created by the script."
        with open(output_csv, "r", newline="") as f:
            actual = f.read().splitlines()

        assert actual == expected, (
            f"Randomized dataset output mismatch: expected {len(expected)} ordered rows, "
            f"got {len(actual)} rows."
        )
        assert len(actual) == len(set(actual)), "Duplicate CSV rows are not allowed."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
