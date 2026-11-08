#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import re
import subprocess
import time

import pytest

AGENT_SCRIPT = "/home/user/audit_wrapper.sh"
PACKAGE_DIR = "/app/libauthtoken-1.2.0"
TOKEN_TOOL = os.path.join(PACKAGE_DIR, "token_tool")
REAL_TOOL = "/tmp/verifier_token_tool.real"
TOOL_LOG = "/tmp/verifier_token_tool.log"
TOOL_MODE = "/tmp/verifier_token_tool.mode"


def create_jwt(sub, exp):
    header = {"alg": "HS256", "typ": "JWT"}
    payload = {}
    if sub is not None:
        payload["sub"] = sub
    if exp is not None:
        payload["exp"] = exp

    h_b64 = base64.urlsafe_b64encode(json.dumps(header).encode()).decode().rstrip("=")
    p_b64 = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
    sig = base64.urlsafe_b64encode(b"fakesig").decode().rstrip("=")
    return f"{h_b64}.{p_b64}.{sig}"


def run_tool(path, token):
    return subprocess.run(
        [path, "validate", token], capture_output=True, text=True, timeout=5
    )


def assert_tool_result(path, token, valid):
    proc = run_tool(path, token)
    if valid:
        assert proc.returncode == 0
        assert proc.stdout == "VALID\n"
    else:
        assert proc.returncode != 0
        assert proc.stdout == "INVALID\n"


def malicious_subject(subject):
    if subject is None:
        return False
    lowered = subject.lower()
    return (
        "<script>" in lowered
        or "union select" in lowered
        or re.search(r"['\"]?\s*or\s+1\s*=\s*1", lowered) is not None
    )


def run_wrapper(token, expected_status, expected_subject, mode="delegate"):
    with open(TOOL_MODE, "w") as f:
        f.write(mode)
    with open(TOOL_LOG, "w"):
        pass

    before = int(time.time())
    proc = subprocess.run(
        [AGENT_SCRIPT, token], capture_output=True, text=True, timeout=5
    )
    after = int(time.time())

    assert proc.returncode == 0, proc.stderr
    match = re.fullmatch(
        r"AUDIT_LOG: status=(VALID|INVALID|MALICIOUS) subject=\[(.*)\] timestamp=([0-9]+)\n?",
        proc.stdout,
    )
    assert match is not None, f"Unexpected stdout: {proc.stdout!r}"
    assert match.group(1) == expected_status
    assert match.group(2) == expected_subject
    assert before <= int(match.group(3)) <= after

    with open(TOOL_LOG) as f:
        calls = [line.rstrip("\n").split("\t", 1) for line in f]
    assert ["validate", token] in calls, (
        "audit_wrapper.sh did not invoke token_tool validate with the supplied token"
    )


@pytest.fixture(scope="session")
def built_tool():
    subprocess.run(["make", "clean"], cwd=PACKAGE_DIR, check=True, timeout=30)
    build = subprocess.run(
        ["make"], cwd=PACKAGE_DIR, capture_output=True, text=True, timeout=30
    )
    assert build.returncode == 0, build.stdout + build.stderr
    assert os.path.isfile(TOKEN_TOOL), f"Compiled token_tool not found at {TOKEN_TOOL}"
    assert os.access(TOKEN_TOOL, os.X_OK), f"token_tool at {TOKEN_TOOL} is not executable"
    return TOKEN_TOOL


@pytest.fixture(scope="session")
def shimmed_tool(built_tool):
    if os.path.exists(REAL_TOOL):
        os.unlink(REAL_TOOL)
    os.replace(TOKEN_TOOL, REAL_TOOL)
    shim = f'''#!/bin/bash
printf '%s\\t%s\\n' "$1" "$2" >> {TOOL_LOG}
mode=$(cat {TOOL_MODE} 2>/dev/null || echo delegate)
if [ "$mode" = valid ]; then
    echo VALID
    exit 0
elif [ "$mode" = invalid ]; then
    echo INVALID
    exit 1
fi
exec {REAL_TOOL} "$@"
'''
    with open(TOKEN_TOOL, "w") as f:
        f.write(shim)
    os.chmod(TOKEN_TOOL, 0o755)

    try:
        yield
    finally:
        if os.path.exists(TOKEN_TOOL):
            os.unlink(TOKEN_TOOL)
        if os.path.exists(REAL_TOOL):
            os.replace(REAL_TOOL, TOKEN_TOOL)
        for path in (TOOL_LOG, TOOL_MODE):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


def test_agent_script_exists_and_executable():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script at {AGENT_SCRIPT} is not executable"


def test_token_tool_compiled_and_fixed(built_tool):
    assert_tool_result(built_tool, '{"sub":"user","exp":0}', True)
    assert_tool_result(built_tool, '{"sub":"user","exp":2147483647}', True)
    assert_tool_result(built_tool, '{"sub":"user"}', False)
    assert_tool_result(built_tool, '{"sub":"user","exp":-1}', False)
    assert_tool_result(built_tool, '{"sub":"user","exp":2147483648}', False)
    assert_tool_result(built_tool, '{"sub":"user","exp":9999999999}', False)


def test_wrapper_honors_tool_and_detects_intrusions(shimmed_tool):
    valid_token = create_jwt("admin", 2000000000)
    run_wrapper(valid_token, "VALID", "admin", mode="valid")
    run_wrapper(valid_token, "INVALID", "admin", mode="invalid")

    for subject in ("<script>alert(1)</script>", "UNION SELECT * FROM users", "' OR 1=1"):
        token = create_jwt(subject, 2000000000)
        run_wrapper(token, "MALICIOUS", subject, mode="valid")
        run_wrapper(token, "MALICIOUS", subject, mode="invalid")


def test_fuzz_behavior(shimmed_tool):
    random.seed(42)
    subjects = [
        "admin",
        "user",
        "<script>alert(1)</script>",
        "UNION SELECT * FROM users",
        "' OR 1=1",
        "normal_user_123",
        None,
    ]
    exps = [
        None,
        1500000000,
        2000000000,
        2147483647,
        2147483648,
        9999999999,
    ]

    for _ in range(1000):
        subject = random.choice(subjects)
        exp = random.choice(exps)
        token = create_jwt(subject, exp)

        tool_proc = run_tool(REAL_TOOL, token)
        if malicious_subject(subject):
            expected_status = "MALICIOUS"
        elif tool_proc.returncode == 0 and tool_proc.stdout == "VALID\n":
            expected_status = "VALID"
        else:
            expected_status = "INVALID"

        run_wrapper(token, expected_status, subject or "", mode="delegate")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
