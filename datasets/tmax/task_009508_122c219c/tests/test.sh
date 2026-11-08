#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import urllib.error
import urllib.request

import pytest

SOLVER = "/home/user/app/solver"
SOURCE = "/home/user/app/solver.c"
REBUILT_SOLVER = "/tmp/verifier_rebuilt_solver"

# Chosen only after the agent has finished. Expected results are independently
# computed rather than stored as a fixed answer table.
_rng = random.SystemRandom()
DIRECT_CASES = sorted(set([1, 4, 8, 10, 12] + _rng.sample(range(2, 12), 4)))
PROXY_CASES = sorted(set([5, 8, 12] + _rng.sample(range(2, 12), 3)))


def queens_count(n):
    mask = (1 << n) - 1

    def search(columns, diag_left, diag_right):
        if columns == mask:
            return 1
        available = mask & ~(columns | diag_left | diag_right)
        total = 0
        while available:
            bit = available & -available
            available -= bit
            total += search(
                columns | bit,
                ((diag_left | bit) << 1) & mask,
                (diag_right | bit) >> 1,
            )
        return total

    return search(0, 0, 0)


def run_solver(path, n, timeout=30):
    result = subprocess.run(
        [path, str(n)], capture_output=True, text=True, timeout=timeout
    )
    assert result.returncode == 0, (
        f"{path} failed for N={n} with status {result.returncode}: {result.stderr}"
    )
    body = result.stdout.strip()
    assert body == str(queens_count(n)), (
        f"Incorrect solver result for N={n}: expected {queens_count(n)}, got {body!r}"
    )


def fetch(n):
    url = f"http://127.0.0.1:8000/qa/{n}"
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            assert response.status == 200, f"Unexpected HTTP status for {url}: {response.status}"
            return response.read().decode("utf-8").strip()
    except urllib.error.URLError as exc:
        pytest.fail(f"Failed to connect to Nginx reverse proxy at {url}: {exc}")


@pytest.fixture(scope="session", autouse=True)
def rebuild_submitted_source():
    assert os.path.isfile(SOURCE), f"Solver source {SOURCE} does not exist."
    result = subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", REBUILT_SOLVER],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Submitted solver.c does not compile:\n{result.stderr}"
    yield
    try:
        os.remove(REBUILT_SOLVER)
    except FileNotFoundError:
        pass


def test_valgrind_log_contents():
    log_path = "/home/user/valgrind.log"
    assert os.path.isfile(log_path), f"Valgrind log file {log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read()
    assert "0 errors from 0 contexts" in content, "Valgrind log does not report '0 errors from 0 contexts'."
    assert "All heap blocks were freed -- no leaks are possible" in content, "Valgrind log does not report that all heap blocks were freed."


def test_solver_binary_no_leaks():
    binary_path = SOLVER
    assert os.path.isfile(binary_path), f"Solver binary {binary_path} does not exist."
    assert os.access(binary_path, os.X_OK), f"Solver binary {binary_path} is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled solver is not an ELF executable."

    # Preserve the original N=8 dynamic Valgrind assertions.
    cmd = ["valgrind", "--leak-check=full", "--error-exitcode=1", binary_path, "8"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=60)
        output = result.stderr
    except subprocess.CalledProcessError as e:
        output = e.stderr
        pytest.fail(f"Valgrind reported errors or leaks when running the fixed solver:\n{output}")

    assert "0 errors from 0 contexts" in output, "Dynamic valgrind check failed: errors found."
    assert "All heap blocks were freed -- no leaks are possible" in output, "Dynamic valgrind check failed: leaks found."
    assert result.stdout.strip() == str(queens_count(8)), "Solver returned an incorrect result under Valgrind for N=8."

    # Independently execute the specifically required N=10 profile rather than
    # trusting strings in the submitted log.
    result10 = subprocess.run(
        ["valgrind", "--leak-check=full", "--show-leak-kinds=all", "--error-exitcode=1", binary_path, "10"],
        capture_output=True,
        text=True,
        timeout=90,
    )
    assert result10.returncode == 0, f"Valgrind failed for N=10:\n{result10.stderr}"
    assert result10.stdout.strip() == str(queens_count(10)), "Solver returned an incorrect result under Valgrind for N=10."
    assert "0 errors from 0 contexts" in result10.stderr
    assert "All heap blocks were freed -- no leaks are possible" in result10.stderr


def test_submitted_source_is_fixed_and_functional():
    with open(REBUILT_SOLVER, "rb") as f:
        assert f.read(4) == b"\x7fELF"

    # Exercise both the installed artifact and a fresh build of solver.c over
    # several inputs, including runtime-selected cases.
    for n in DIRECT_CASES:
        run_solver(SOLVER, n)
        run_solver(REBUILT_SOLVER, n)

    result = subprocess.run(
        ["valgrind", "--leak-check=full", "--error-exitcode=1", REBUILT_SOLVER, "10"],
        capture_output=True,
        text=True,
        timeout=90,
    )
    assert result.returncode == 0, f"Freshly compiled solver.c is not memory-safe:\n{result.stderr}"
    assert result.stdout.strip() == str(queens_count(10))
    assert "0 errors from 0 contexts" in result.stderr
    assert "All heap blocks were freed -- no leaks are possible" in result.stderr


def test_services_running():
    try:
        subprocess.run(["pgrep", "-f", "backend.py"], check=True, stdout=subprocess.PIPE)
    except subprocess.CalledProcessError:
        pytest.fail("Python backend (backend.py) is not running.")

    try:
        subprocess.run(["pgrep", "nginx"], check=True, stdout=subprocess.PIPE)
    except subprocess.CalledProcessError:
        pytest.fail("Nginx is not running.")


def test_response_txt():
    response_path = "/home/user/response.txt"
    assert os.path.isfile(response_path), f"Response file {response_path} does not exist."
    with open(response_path, "r") as f:
        content = f.read().strip()
    assert content == "14200", f"Expected response.txt to contain '14200', but got '{content}'."

    # Confirm the saved body agrees with the currently operating N=12 route.
    assert fetch(12) == content, "response.txt does not match the live /qa/12 response."


def test_nginx_proxy_endpoint():
    # Preserve the original N=8 proxy assertion.
    body = fetch(8)
    assert body == "92", f"Expected proxy endpoint to return '92' for N=8, but got '{body}'"

    # Verify URI rewriting and solver execution for multiple independently
    # derived cases, preventing a fixed '92' responder from passing.
    for n in PROXY_CASES:
        body = fetch(n)
        expected = str(queens_count(n))
        assert body == expected, f"Expected proxy endpoint to return {expected} for N={n}, but got {body!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
