#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import signal
import socket
import string
import subprocess
import time
import pytest

BINARY = "/home/user/tinyserver_patched"
EVAL_SCRIPT = "/app/evaluate_server.py"


def test_tinyserver_patched_exists_and_executable():
    assert os.path.isfile(BINARY), f"The patched binary does not exist at {BINARY}."
    assert os.access(BINARY, os.X_OK), f"The patched binary at {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The patched executable must be a compiled ELF binary."


def test_evaluation_score():
    assert os.path.isfile(EVAL_SCRIPT), f"Evaluation script {EVAL_SCRIPT} is missing."

    proc = subprocess.Popen(
        ["python3", EVAL_SCRIPT, BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    try:
        out, _ = proc.communicate(timeout=30)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        out, _ = proc.communicate()
        pytest.fail(f"Evaluation script timed out. Output:\n{out}")
    finally:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    assert proc.returncode == 0, (
        f"Evaluation script failed with exit code {proc.returncode}. Output:\n{out}"
    )

    # The evaluator prints its own score only after the submitted process has
    # terminated. Use the last complete SCORE line so a submission cannot
    # inject an earlier self-reported score.
    scores = []
    for line in out.splitlines():
        match = re.fullmatch(r"\s*SCORE:\s*([0-9]+(?:\.[0-9]+)?)\s*", line)
        if match:
            scores.append(float(match.group(1)))

    assert scores, f"Could not find a complete 'SCORE:' line in evaluation output. Output:\n{out}"
    score = scores[-1]
    assert score >= 1.0, f"Expected accuracy score >= 1.0, but got {score}. Output:\n{out}"


def get_free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def request(port, user, password, payload, timeout=1.5):
    with socket.create_connection(("127.0.0.1", port), timeout=timeout) as sock:
        sock.settimeout(timeout)
        sock.sendall(f"{user} {password} {payload}".encode("ascii"))
        return sock.recv(1024).decode("ascii", errors="replace").strip()


def test_randomized_network_behavior_and_survival():
    port = get_free_port()
    proc = subprocess.Popen(
        [BINARY, str(port)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )

    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits + "_-"

    def token(min_len, max_len):
        return "".join(rng.choice(alphabet) for _ in range(rng.randint(min_len, max_len)))

    try:
        deadline = time.time() + 5
        while True:
            if proc.poll() is not None:
                pytest.fail(f"Patched server exited during startup with code {proc.returncode}.")
            try:
                if request(port, "user", "pass", token(4, 24)) == "OK":
                    break
            except OSError:
                pass
            if time.time() >= deadline:
                pytest.fail("Patched server did not begin accepting valid requests.")
            time.sleep(0.05)

        cases = []
        for _ in range(12):
            cases.append(("user", "pass", token(1, 120), "OK"))

        for _ in range(12):
            wrong_password = token(4, 30)
            if wrong_password == "pass":
                wrong_password += "x"
            cases.append(("user", wrong_password, token(1, 120), "DENIED"))

        for _ in range(12):
            cases.append(("admin", token(4, 30), token(1, 120), "DENIED"))

        for _ in range(12):
            username = token(4, 30)
            if username in ("user", "admin"):
                username += "x"
            cases.append((username, token(4, 30), token(1, 120), "DENIED"))

        rng.shuffle(cases)
        for user, password, payload, expected in cases:
            actual = request(port, user, password, payload)
            assert actual == expected, (
                f"Unexpected response for credentials {user!r}/{password!r}: "
                f"expected {expected!r}, got {actual!r}."
            )
            assert proc.poll() is None, "Patched server exited while handling ordinary requests."

        # Exercise varied payloads larger than the vulnerable 128-byte decode
        # destination, and verify both an allowed protocol response and continued
        # service after each request.
        for _ in range(16):
            oversized = token(180, 900)
            actual = request(port, "user", "pass", oversized)
            assert actual in {"OK", "ERROR", "DENIED"}, (
                f"Oversized payload produced invalid response {actual!r}."
            )
            assert proc.poll() is None, "Patched server crashed on an oversized payload."
            assert request(port, "user", "pass", token(5, 40)) == "OK", (
                "Server stopped correctly processing requests after an oversized payload."
            )

        # Authentication must still be checked before processing oversized data.
        for _ in range(8):
            oversized = token(180, 900)
            assert request(port, "admin", token(5, 20), oversized) == "DENIED"
            assert proc.poll() is None, "Patched server crashed on adversarial credentials/payload."
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=2)
        except ProcessLookupError:
            pass
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
