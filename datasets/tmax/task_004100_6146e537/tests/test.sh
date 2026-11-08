#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import socket
import subprocess
import time
from pathlib import Path

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080/evaluate"
AUTH_HEADER = {"Authorization": "Bearer 32"}
ROOT = Path("/home/user/evaluator")
SERVER = ROOT / "matheval_server"
SEED = secrets.randbits(64)
RNG = random.Random(SEED)


def trunc_div(a, b):
    assert b != 0
    q = abs(a) // abs(b)
    return -q if (a < 0) != (b < 0) else q


def expected_value(expr):
    numbers = []
    operators = []
    current = ""
    for ch in expr:
        if ch.isdigit():
            current += ch
        else:
            assert current and ch in "+-*/"
            numbers.append(int(current))
            operators.append(ch)
            current = ""
    assert current
    numbers.append(int(current))

    reduced_numbers = [numbers[0]]
    reduced_ops = []
    for op, value in zip(operators, numbers[1:]):
        if op == "*":
            reduced_numbers[-1] *= value
        elif op == "/":
            reduced_numbers[-1] = trunc_div(reduced_numbers[-1], value)
        else:
            reduced_ops.append(op)
            reduced_numbers.append(value)

    result = reduced_numbers[0]
    for op, value in zip(reduced_ops, reduced_numbers[1:]):
        result = result + value if op == "+" else result - value
    return result


def generated_cases():
    cases = []
    for op in "+-*/":
        a = RNG.randint(2, 500)
        b = RNG.randint(1, 50)
        cases.append(f"{a}{op}{b}")
    for _ in range(24):
        count = RNG.randint(3, 7)
        nums = [RNG.randint(1, 40) for _ in range(count)]
        ops = [RNG.choice("+-*/") for _ in range(count - 1)]
        cases.append("".join(str(nums[i]) + ops[i] for i in range(count - 1)) + str(nums[-1]))
    return cases


DYNAMIC_CASES = generated_cases()


def kill_port_8080():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].endswith(":1F90") and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    victims = set()
    if inodes:
        for entry in os.listdir("/proc"):
            if not entry.isdigit():
                continue
            fd_dir = f"/proc/{entry}/fd"
            try:
                for fd in os.listdir(fd_dir):
                    try:
                        target = os.readlink(f"{fd_dir}/{fd}")
                    except OSError:
                        continue
                    if target.startswith("socket:[") and target[8:-1] in inodes:
                        victims.add(int(entry))
                        break
            except OSError:
                continue
    for pid in victims:
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.3)


def build_parser_probe(tmp_path):
    source = tmp_path / "parser_probe.cpp"
    binary = tmp_path / "parser_probe"
    source.write_text(r'''#include "parser.h"
#include <iostream>
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    std::cout << evaluate_expression(argv[1]);
    return 0;
}
''')
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", "-I", str(ROOT), str(source),
         str(ROOT / "parser.cpp"), "-o", str(binary)],
        text=True, capture_output=True, timeout=30,
    )
    assert result.returncode == 0, f"parser.cpp does not compile with its public interface:\n{result.stdout}\n{result.stderr}"
    return binary


@pytest.fixture(scope="session", autouse=True)
def build_and_run_submitted_artifact(tmp_path_factory):
    assert (ROOT / "Makefile").is_file(), f"Makefile is missing at {ROOT / 'Makefile'}."

    kill_port_8080()
    try:
        SERVER.unlink()
    except FileNotFoundError:
        pass

    built = subprocess.run(
        ["make", "-B"], cwd=ROOT, text=True, capture_output=True, timeout=45
    )
    assert built.returncode == 0, f"Makefile build failed:\n{built.stdout}\n{built.stderr}"
    assert SERVER.is_file(), "Makefile did not create matheval_server."
    assert os.access(SERVER, os.X_OK), "matheval_server is not executable."
    with open(SERVER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "matheval_server is not a compiled ELF executable."

    probe = build_parser_probe(tmp_path_factory.mktemp("parser_probe"))
    for expr in DYNAMIC_CASES:
        run = subprocess.run([str(probe), expr], text=True, capture_output=True, timeout=5)
        assert run.returncode == 0, f"evaluate_expression failed for {expr!r} (seed {SEED})."
        assert run.stdout.strip() == str(expected_value(expr)), (
            f"evaluate_expression({expr!r}) returned {run.stdout!r}; "
            f"expected {expected_value(expr)} (seed {SEED})."
        )

    kill_port_8080()
    log = open("/tmp/matheval_server.log", "wb")
    process = subprocess.Popen(
        [str(SERVER)], cwd=ROOT, stdin=subprocess.DEVNULL,
        stdout=log, stderr=subprocess.STDOUT, start_new_session=True,
    )

    last_error = None
    for _ in range(50):
        if process.poll() is not None:
            break
        try:
            response = requests.post(BASE_URL, data="1+1", timeout=0.5)
            if response.status_code == 401:
                break
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.1)
    else:
        pytest.fail(f"Compiled matheval_server did not listen on port 8080: {last_error}")

    assert process.poll() is None, "Compiled matheval_server exited instead of serving requests."
    yield


def test_makefile_exists():
    makefile_path = "/home/user/evaluator/Makefile"
    assert os.path.isfile(makefile_path), f"Makefile is missing at {makefile_path}."


def test_parser_patched():
    parser_path = "/home/user/evaluator/parser.cpp"
    assert os.path.isfile(parser_path), f"parser.cpp is missing at {parser_path}."
    with open(parser_path, "r") as f:
        content = f.read()
    assert "int result = left * right;" in content, "parser.cpp does not seem to be patched correctly with the multiplication fix."


def test_unauthorized_missing_header():
    try:
        response = requests.post(BASE_URL, data="7*6", timeout=5)
        assert response.status_code == 401, f"Expected 401 Unauthorized for missing auth header, got {response.status_code}. Response: {response.text}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server or request timed out: {e}")


def test_unauthorized_wrong_header():
    try:
        response = requests.post(BASE_URL, headers={"Authorization": "Bearer 999"}, data="7*6", timeout=5)
        assert response.status_code == 401, f"Expected 401 Unauthorized for incorrect auth header, got {response.status_code}. Response: {response.text}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server or request timed out: {e}")


def test_authorized_evaluate_multiplication():
    try:
        response = requests.post(BASE_URL, headers=AUTH_HEADER, data="7*6", timeout=5)
        assert response.status_code == 200, f"Expected 200 OK for valid request, got {response.status_code}. Response: {response.text}"
        assert response.text.strip() == "42", f"Expected '42' as the evaluation result, got '{response.text}'"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server or request timed out: {e}")


def test_authorized_evaluate_addition():
    try:
        response = requests.post(BASE_URL, headers=AUTH_HEADER, data="10+15", timeout=5)
        assert response.status_code == 200, f"Expected 200 OK for valid request, got {response.status_code}. Response: {response.text}"
        assert response.text.strip() == "25", f"Expected '25' as the evaluation result, got '{response.text}'"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server or request timed out: {e}")


def test_randomized_general_expression_evaluation():
    for expr in DYNAMIC_CASES:
        response = requests.post(BASE_URL, headers=AUTH_HEADER, data=expr, timeout=5)
        expected = str(expected_value(expr))
        assert response.status_code == 200, (
            f"Expected 200 for {expr!r}, got {response.status_code} (seed {SEED})."
        )
        assert response.text == expected, (
            f"For {expr!r}, expected exact body {expected!r}, got {response.text!r} (seed {SEED})."
        )


def test_authorization_value_is_strict():
    wrong_values = ["Bearer 032", "Bearer 32 extra", "32", f"Bearer {RNG.randint(1000, 999999)}"]
    for value in wrong_values:
        response = requests.post(BASE_URL, headers={"Authorization": value}, data="3*9", timeout=5)
        assert response.status_code == 401, f"Authorization value {value!r} was incorrectly accepted."
        assert response.content == b"", "Unauthorized response must have an empty body."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
