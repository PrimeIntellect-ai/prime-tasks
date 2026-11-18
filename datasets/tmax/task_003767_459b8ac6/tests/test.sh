#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import secrets
import subprocess
import tempfile
import pytest

SCRIPT_PATH = "/home/user/detector.py"


def run_detector(log_path):
    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH, log_path],
            capture_output=True,
            text=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Script {SCRIPT_PATH} timed out after 15 seconds.")
    except Exception as e:
        pytest.fail(f"Failed to execute script {SCRIPT_PATH}: {e}")

    assert result.returncode == 0, (
        f"Script exited with non-zero status code {result.returncode}.\n"
        f"Stderr: {result.stderr}"
    )
    return {line.strip() for line in result.stdout.splitlines() if line.strip()}


def assert_f1(expected_ids, output_ids):
    tp = len(expected_ids.intersection(output_ids))
    fp = len(output_ids - expected_ids)
    fn = len(expected_ids - output_ids)

    if tp == 0:
        f1 = 0.0
    else:
        f1 = 2 * tp / (2 * tp + fp + fn)

    assert f1 >= 0.95, (
        f"F1 Score {f1:.4f} is below the threshold of 0.95. "
        f"Expected IDs: {expected_ids}, Output IDs: {output_ids}"
    )


def test_detector_script_f1_score():
    test_log_path = "/hidden/test_log.json"

    assert os.path.isfile(SCRIPT_PATH), f"Detector script not found at {SCRIPT_PATH}"
    assert os.path.isfile(test_log_path), f"Hidden test log not found at {test_log_path}"

    expected_ids = {
        "req_102", "req_105", "req_110", "req_111",
        "req_119", "req_120", "req_135", "req_142",
    }
    assert_f1(expected_ids, run_detector(test_log_path))


def b64(value):
    return base64.b64encode(value.encode()).decode()


def make_random_log():
    nonce = secrets.token_hex(12)
    rows = []
    expected = set()
    counter = 0

    def add(path="/index.html", headers=None, malicious=False):
        nonlocal counter
        request_id = f"audit_{nonce}_{counter}_{secrets.token_hex(4)}"
        counter += 1
        rows.append({
            "request_id": request_id,
            "method": "GET",
            "path": path,
            "headers": headers or {},
        })
        if malicious:
            expected.add(request_id)

    # Cookie-based positives.
    add(headers={"Cookie": f"session_data={b64('admin=true')}"}, malicious=True)
    add(headers={"Cookie": f"theme=dark; session_data={b64('prefix admin=true suffix')}"}, malicious=True)
    add(headers={"Cookie": f"a=1;session_data={b64('xxadmin=trueyy')};b=2"}, malicious=True)
    add(headers={"Cookie": f"session_data={b64('role=user;admin=true;active=1')}"}, malicious=True)

    # Traversal positives, including URL-encoded spellings.
    add(path="/files/../secret", malicious=True)
    add(path="/files/..%2Fsecret", malicious=True)
    add(path="/files/%2e%2e%2fsecret", malicious=True)
    add(path="/download?name=one%2F..%2Ftwo", malicious=True)

    # X-Forwarded-For positives.
    add(headers={"X-Forwarded-For": "203.0.113.5; id"}, malicious=True)
    add(headers={"X-Forwarded-For": "203.0.113.6|whoami"}, malicious=True)
    add(headers={"X-Forwarded-For": "203.0.113.7$PATH"}, malicious=True)
    add(headers={"X-Forwarded-For": "198.51.100.2, 203.0.113.8 | cat"}, malicious=True)

    # Benign controls prevent scripts that simply print every request ID.
    add(headers={"Cookie": f"session_data={b64('admin=false')}"})
    add(headers={"Cookie": f"session_data={b64('Admin=true')}"})
    add(headers={"Cookie": f"other_data={b64('admin=true')}"})
    add(headers={"Cookie": f"session_data={b64('user=true;admin=false')}"})
    add(path="/files/..%5Csecret")
    add(path="/files/dots..%2Fsecret")
    add(path="/ordinary/path")
    add(headers={"X-Forwarded-For": "203.0.113.9, 198.51.100.4"})
    add(headers={"User-Agent": "scanner; id", "X-Forwarded-For": "203.0.113.10"})
    add(path="/price/$5", headers={"X-Forwarded-For": "203.0.113.11"})

    random.SystemRandom().shuffle(rows)
    return rows, expected


def test_detector_on_unpredictable_logs():
    assert os.path.isfile(SCRIPT_PATH), f"Detector script not found at {SCRIPT_PATH}"

    # Separate, freshly generated files ensure the detector actually consumes its argument.
    for _ in range(3):
        rows, expected_ids = make_random_log()
        fd, log_path = tempfile.mkstemp(prefix="detector_audit_", suffix=".json")
        try:
            with os.fdopen(fd, "w") as log_file:
                for row in rows:
                    log_file.write(json.dumps(row) + "\n")
            assert_f1(expected_ids, run_detector(log_path))
        finally:
            if os.path.exists(log_path):
                os.unlink(log_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
