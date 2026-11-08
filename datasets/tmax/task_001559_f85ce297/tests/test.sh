#!/bin/bash
set -u
mkdir -p /logs/verifier

ORACLE_PATH=/app/oracle_processor
FIXTURE_PATH=/tmp/oracle_expected.pkl
ORACLE_MODE=""
reward=0

cleanup() {
    if [ -n "$ORACLE_MODE" ] && [ -e "$ORACLE_PATH" ]; then
        chmod "$ORACLE_MODE" "$ORACLE_PATH" 2>/dev/null || true
    fi
    echo "$reward" > /logs/verifier/reward.txt
}
trap cleanup EXIT

if [ ! -f "$ORACLE_PATH" ]; then
    exit 1
fi
ORACLE_MODE=$(stat -c '%a' "$ORACLE_PATH") || exit 1

# Derive all fuzz answers from the reference before making it unavailable to
# submitted code. The processor is later run as the unprivileged agent user.
python3 - <<'PY' || exit 1
import hashlib
import pickle
import random
import string
import subprocess

oracle = "/app/oracle_processor"
random.seed(42)
cases = []
for i in range(100):
    length = random.randint(0, 5000)
    input_data = "".join(random.choice(string.printable) for _ in range(length)).encode("utf-8")
    proc = subprocess.run([oracle], input=input_data, capture_output=True)
    if proc.returncode != 0:
        raise SystemExit(f"Oracle failed on input {i}")
    cases.append((input_data, proc.stdout))

with open(oracle, "rb") as f:
    oracle_digest = hashlib.sha256(f.read()).hexdigest()
with open("/tmp/oracle_expected.pkl", "wb") as f:
    pickle.dump({"cases": cases, "oracle_digest": oracle_digest}, f)
PY

# Prevent processor.py from delegating its work to the reference binary.
chmod 000 "$ORACLE_PATH" || exit 1

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import os
import pickle
import pwd
import subprocess
import urllib.error
import urllib.request
import pytest

ORACLE_PATH = "/app/oracle_processor"
AGENT_PATH = "/home/user/processor.py"

with open("/tmp/oracle_expected.pkl", "rb") as f:
    FIXTURE = pickle.load(f)


def run_as_agent(argv, input_data):
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return subprocess.run(
        argv,
        input=input_data,
        capture_output=True,
        preexec_fn=demote,
    )


def test_fuzz_equivalence():
    """Test that the agent's processor script perfectly matches the oracle binary."""
    assert os.path.isfile(AGENT_PATH), f"Agent script missing: {AGENT_PATH}"
    assert os.path.isfile(ORACLE_PATH), f"Oracle missing: {ORACLE_PATH}"

    # The requested artifact must be genuine parseable Python source, not the
    # reference executable copied into the destination path.
    with open(AGENT_PATH, "rb") as f:
        agent_bytes = f.read()
    assert hashlib.sha256(agent_bytes).hexdigest() != FIXTURE["oracle_digest"], \
        "processor.py is byte-identical to the reference executable"
    try:
        source = agent_bytes.decode("utf-8")
        ast.parse(source, filename=AGENT_PATH)
    except (UnicodeDecodeError, SyntaxError) as exc:
        pytest.fail(f"processor.py is not valid UTF-8 Python source: {exc}")

    for i, (input_data, oracle_out) in enumerate(FIXTURE["cases"]):
        agent_proc = run_as_agent(["python3", AGENT_PATH], input_data)
        assert agent_proc.returncode == 0, (
            f"Agent script failed on input {i}. Stderr: "
            f"{agent_proc.stderr.decode(errors='replace')}"
        )
        agent_out = agent_proc.stdout
        if oracle_out != agent_out:
            pytest.fail(
                f"Mismatch on input {i} (length {len(input_data)}).\n"
                f"Input data (repr): {input_data!r}\n"
                f"Expected (Oracle): {oracle_out!r}\n"
                f"Got (Agent): {agent_out!r}"
            )


def test_end_to_end_service():
    """Test that the Nginx -> Gunicorn -> Flask -> processor.py pipeline works end-to-end."""
    url = "http://127.0.0.1:8080/process"
    data = b"Hello World"

    try:
        req = urllib.request.Request(url, data=data, method="POST")
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected HTTP 200, got {response.status}"
            body = response.read()
            expected = b"qlyeJ byyrU"
            assert body == expected, f"End-to-end transformation failed. Expected {expected!r}, got {body!r}"
    except urllib.error.HTTPError as e:
        pytest.fail(f"HTTP Error received from Nginx: {e.code} {e.reason}")
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx at {url}: {e.reason}")
    except Exception as e:
        pytest.fail(f"Unexpected error during end-to-end request: {e}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi
exit 0
