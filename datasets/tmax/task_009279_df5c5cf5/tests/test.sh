#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PLUGIN_EOF' > /tmp/trace_regression_plugin.py
import os
import sys

_seen_exact_call = False
_expected_payload = bytes.fromhex(os.environ["EXPECTED_CRASH_HEX"])
_processor_path = os.path.realpath("/home/user/ticket_4092/processor.py")
_trace_result = os.environ["TRACE_RESULT"]


def _trace(frame, event, arg):
    global _seen_exact_call
    if event == "call":
        code = frame.f_code
        if code.co_name == "deserialize" and os.path.realpath(code.co_filename) == _processor_path:
            caller = frame.f_back
            in_regression_test = False
            while caller is not None:
                if caller.f_code.co_name == "test_regression_cve_2023_memory":
                    in_regression_test = True
                    break
                caller = caller.f_back
            if in_regression_test and frame.f_locals.get("data") == _expected_payload:
                _seen_exact_call = True
    return _trace


def pytest_sessionstart(session):
    sys.settrace(_trace)


def pytest_sessionfinish(session, exitstatus):
    sys.settrace(None)
    with open(_trace_result, "w", encoding="ascii") as f:
        f.write("1" if _seen_exact_call else "0")
PLUGIN_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import importlib.util
import os
import random
import re
import subprocess
import sys

import pytest

ROOT = "/home/user/ticket_4092"


def crash_payload_from_dump():
    with open(os.path.join(ROOT, "memory.dmp"), "rb") as f:
        dump = f.read()
    marker = b"CRASH_CONTEXT:"
    pos = dump.find(marker)
    assert pos >= 0, "CRASH_CONTEXT marker is missing from memory.dmp"
    encoded_tail = dump[pos + len(marker):]
    match = re.match(rb"[A-Za-z0-9+/]+={0,2}", encoded_tail)
    assert match, "No base64 payload follows CRASH_CONTEXT"
    return base64.b64decode(match.group(0), validate=True)


def load_processor():
    path = os.path.join(ROOT, "processor.py")
    assert os.path.isfile(path), "processor.py is missing or is not a file."
    spec = importlib.util.spec_from_file_location("verified_processor", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_extracted_payload():
    path = os.path.join(ROOT, "extracted_payload.txt")
    assert os.path.exists(path), "extracted_payload.txt is missing."
    with open(path, "r") as f:
        content = f.read().strip()
    expected = "435553547c313530303023696e76616c69645f757466385fff"
    assert content.lower() == expected, f"extracted_payload.txt content is incorrect. Expected {expected}, got {content}"
    assert content.lower() == crash_payload_from_dump().hex(), "The documented hex does not match the payload in memory.dmp."


def test_processor_fixes():
    processor = load_processor()

    # Preserve the original fixed checks.
    with pytest.raises(ValueError, match="Payload too large"):
        processor.deserialize(b"CUST|1001#abc")

    try:
        res = processor.deserialize(b"CUST|4#\xff\xff\xff\xff")
    except UnicodeDecodeError:
        pytest.fail("UnicodeDecodeError was raised. The decoding step does not gracefully handle invalid bytes.")
    assert isinstance(res, str), "deserialize should still return a string when processing invalid utf-8 bytes."

    # Exercise randomized lengths and payloads so the implementation cannot
    # special-case the two original byte strings.
    rng = random.SystemRandom()
    for _ in range(20):
        length = rng.randint(1001, 500000)
        body = os.urandom(rng.randint(0, 40))
        with pytest.raises(ValueError) as exc:
            processor.deserialize(b"CUST|" + str(length).encode("ascii") + b"#" + body)
        assert str(exc.value) == "Payload too large"

    samples = [(1000, b"A" * 999 + b"\xff")]
    for _ in range(20):
        length = rng.randint(0, 1000)
        body = os.urandom(length + rng.randint(0, 12))
        samples.append((length, body))

    for length, body in samples:
        expected = body[:length].decode("utf-8", errors="replace")
        actual = processor.deserialize(b"CUST|" + str(length).encode("ascii") + b"#" + body)
        assert actual == expected


def test_regression_test_file():
    path = os.path.join(ROOT, "test_processor.py")
    assert os.path.exists(path), "test_processor.py is missing."
    assert os.path.isfile(path), "test_processor.py is not a regular test file."
    with open(path, "r") as f:
        content = f.read()
    assert "def test_regression_cve_2023_memory" in content, "test_regression_cve_2023_memory() function is missing in test_processor.py."
    assert "ValueError" in content, "The test does not seem to check for ValueError."
    assert "Payload too large" in content, "The test does not seem to check for the 'Payload too large' message."

    payload = crash_payload_from_dump()
    trace_result = "/tmp/regression_trace_result"
    try:
        os.unlink(trace_result)
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    env["EXPECTED_CRASH_HEX"] = payload.hex()
    env["TRACE_RESULT"] = trace_result
    env["PYTHONPATH"] = "/tmp" + os.pathsep + env.get("PYTHONPATH", "")
    completed = subprocess.run(
        [sys.executable, "-m", "pytest", "--noconftest", "-p", "trace_regression_plugin", path, "-q"],
        cwd=ROOT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert completed.returncode == 0, "The submitted regression test does not pass:\n" + completed.stdout
    assert os.path.exists(trace_result), "Regression-test execution was not observed."
    with open(trace_result, "r", encoding="ascii") as f:
        observed = f.read()
    assert observed == "1", "test_regression_cve_2023_memory did not call deserialize with the exact crashing bytes."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
