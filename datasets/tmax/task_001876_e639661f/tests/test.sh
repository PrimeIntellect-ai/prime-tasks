#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import os
import re
import secrets
import subprocess

SO_PATH = "/home/user/src/libratelimit.so"
SCRIPT_PATH = "/home/user/test_api.py"
REQUESTS_PATH = "/home/user/requests.txt"
LOG_PATH = "/home/user/api_results.log"


def run_script():
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"test_api.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_shared_library_compiled():
    """Verify that libratelimit.so was compiled."""
    assert os.path.isfile(SO_PATH), f"{SO_PATH} does not exist. Did you compile the library?"


def test_shared_library_abi():
    """Verify that allow_request is exported with C ABI (no mangling)."""
    assert os.path.isfile(SO_PATH), f"{SO_PATH} missing."

    result = subprocess.run(["nm", "-D", SO_PATH], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to run nm on the shared library."

    symbols = result.stdout.splitlines()
    found_unmangled = any(line.endswith(" allow_request") for line in symbols)
    assert found_unmangled, "Could not find unmangled 'allow_request' in the shared library. Did you add extern \"C\"?"


def test_shared_library_behavior():
    """Load and exercise the exported function through ctypes."""
    lib = ctypes.CDLL(SO_PATH)
    allow_request = lib.allow_request
    allow_request.argtypes = [ctypes.c_uint32, ctypes.c_uint32]
    allow_request.restype = ctypes.c_int

    client_a = secrets.randbelow(400) + 1
    client_b = client_a + 401
    assert allow_request(client_a, 2) == 1
    assert allow_request(client_a, 2) == 1
    assert allow_request(client_a, 2) == 0
    assert allow_request(client_b, 1) == 1
    assert allow_request(client_b, 1) == 0


def test_python_script_exists():
    """Verify that the test_api.py script exists."""
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist."


def test_api_results_log():
    """Execute the script and verify the required fixed input output."""
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)
    run_script()

    assert os.path.isfile(LOG_PATH), f"{LOG_PATH} does not exist. Did you run your Python script?"
    with open(LOG_PATH, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "ACCEPTED: 12:GET /api/v1/users",
        "ACCEPTED: 12:POST /api/v1/data",
        "ACCEPTED: 45:GET /status",
        "REJECTED: 12:DELETE /api/v1/users/1",
        "ACCEPTED: 45:POST /login",
        "REJECTED: 45:GET /dashboard",
        "REJECTED: 12:GET /retry"
    ]

    assert actual_lines == expected_lines, "The contents of api_results.log do not match the expected output. Check your rate limiting, logging format, and malformed line handling."


def test_script_on_unseen_requests():
    """Exercise test_api.py on verifier-generated requests and derive the answers."""
    with open(REQUESTS_PATH, "rb") as f:
        original_requests = f.read()
    original_log = None
    if os.path.exists(LOG_PATH):
        with open(LOG_PATH, "rb") as f:
            original_log = f.read()

    ids = secrets.SystemRandom().sample(range(100, 900), 3)
    a, b, c = ids
    token = secrets.token_hex(8)
    lines = [
        f"{a}:GET /generated/{token}",
        "INVALID_LINE",
        f"{b}:payload:with:colons-{token}",
        f"{a}:POST payload {token}",
        "malformed:request",
        f"{a}:third request {token}",
        f"{b}:second request {token}  ",
        "0:not-positive",
        f"{b}:third request {token}",
        "-7:not-positive",
        f"{c}:final {token}",
    ]

    counts = {}
    expected = []
    valid_pattern = re.compile(r"^([1-9][0-9]*):(.*)$")
    for line in lines:
        match = valid_pattern.fullmatch(line)
        if not match:
            continue
        client_id = int(match.group(1))
        counts[client_id] = counts.get(client_id, 0) + 1
        decision = "ACCEPTED" if counts[client_id] <= 2 else "REJECTED"
        expected.append(f"{decision}: {line}")

    try:
        with open(REQUESTS_PATH, "w", newline="") as f:
            f.write("\n".join(lines) + "\n")
        if os.path.exists(LOG_PATH):
            os.remove(LOG_PATH)

        run_script()
        assert os.path.isfile(LOG_PATH), "test_api.py did not create api_results.log"
        with open(LOG_PATH, "r", newline="") as f:
            actual = f.read().splitlines()
        assert actual == expected, (
            "test_api.py failed on verifier-generated requests; check strict validation, "
            "ctypes calls, per-client limiting, output replacement, and exact line preservation."
        )
    finally:
        with open(REQUESTS_PATH, "wb") as f:
            f.write(original_requests)
        if original_log is None:
            if os.path.exists(LOG_PATH):
                os.remove(LOG_PATH)
        else:
            with open(LOG_PATH, "wb") as f:
                f.write(original_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
