#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import socket
import subprocess
import time

import pytest

REPO = "/app/math_server"
HOST = "127.0.0.1"
PORT = 8888
SERVER_PROCESS = None


def strip_cpp_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def reference_root(x, tolerance):
    for _ in range(1000):
        fx = x * x * x - 2.0 * x - 5.0
        if abs(fx) <= tolerance:
            return x
        dfx = 3.0 * x * x - 2.0
        x = x - fx / dfx
    raise AssertionError("Reference Newton iteration did not converge")


def request(payload, timeout=5):
    with socket.create_connection((HOST, PORT), timeout=timeout) as s:
        s.sendall(payload)
        data = b""
        while not data.endswith(b"\n"):
            chunk = s.recv(1024)
            if not chunk:
                break
            data += chunk
        return data.decode("utf-8")


@pytest.fixture(scope="session", autouse=True)
def rebuild_and_start_submission():
    global SERVER_PROCESS

    # Ensure the live service tested below is a clean build of the submitted source,
    # rather than an unrelated process left listening on the requested port.
    subprocess.run(["pkill", "-x", "server"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["make", "clean"], cwd=REPO, check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    subprocess.run(["make"], cwd=REPO, check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    binary = os.path.join(REPO, "server")
    assert os.path.isfile(binary), "Build did not produce /app/math_server/server"
    assert os.access(binary, os.X_OK), "Built server is not executable"
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Built server is not an ELF executable"

    SERVER_PROCESS = subprocess.Popen(
        [binary], cwd=REPO, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True
    )
    deadline = time.time() + 5
    while time.time() < deadline:
        if SERVER_PROCESS.poll() is not None:
            pytest.fail("The rebuilt server exited before accepting connections")
        try:
            with socket.create_connection((HOST, PORT), timeout=0.2):
                break
        except OSError:
            time.sleep(0.05)
    else:
        pytest.fail(f"Could not connect to rebuilt server at {HOST}:{PORT}")

    # Deliberately leave the verified server running after pytest exits, as required.
    yield


def test_makefile_fixed():
    makefile_path = "/app/math_server/Makefile"
    assert os.path.isfile(makefile_path), f"{makefile_path} does not exist"
    with open(makefile_path, "r") as f:
        content = f.read()
    assert "math_utils.o" in content.split("server:")[1].split("\n")[1], "Makefile still has linker error"

    uncommented = re.sub(r"(?m)#.*$", "", content)
    link_lines = re.findall(r"(?m)^\s*g\+\+\s+-o\s+server[^\n]*$", uncommented)
    assert any("math_utils.o" in line for line in link_lines), \
        "The actual server link command does not link math_utils.o"


def test_math_utils_fixed():
    math_utils_path = "/app/math_server/math_utils.cpp"
    assert os.path.isfile(math_utils_path), f"{math_utils_path} does not exist"
    with open(math_utils_path, "r") as f:
        content = f.read()
    assert "x = x - f(x) / df(x);" in content, "math_utils.cpp still has the mathematical regression"
    assert "x = x + f(x) / df(x);" not in content, "math_utils.cpp still has the mathematical regression"

    code = strip_cpp_comments(content)
    assert "x = x - f(x) / df(x);" in code, \
        "The Newton-Raphson subtraction update is not executable code"
    assert "x = x + f(x) / df(x);" not in code, \
        "The corrupted addition update remains in executable code"


def test_main_cpp_updated():
    main_path = "/app/math_server/main.cpp"
    assert os.path.isfile(main_path), f"{main_path} does not exist"
    with open(main_path, "r") as f:
        content = f.read()
    assert "8888" in content, "main.cpp does not have the updated port 8888"
    assert "1e-6" in content or "0.000001" in content, "main.cpp does not have the updated tolerance"

    code = strip_cpp_comments(content)
    assert re.search(r"\bport\s*=\s*8888\b", code), "Port 8888 is only present in a comment or unrelated text"
    assert re.search(r"\btolerance\s*=\s*(?:1e-6|0\.000001)\b", code), \
        "Tolerance 1e-6 is only present in a comment or unrelated text"
    assert re.search(r"find_root\s*\(\s*x0\s*,\s*tolerance\s*\)", code), \
        "The request path does not call find_root with the configured tolerance"


def test_find_root_matches_derived_newton_iterations():
    # Exercise find_root directly at full precision. Loose and randomly selected
    # tolerances expose constant-root implementations that wire tests rounded to
    # five decimal places cannot distinguish.
    probe_source = r'''
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include "math_utils.h"
int main(int argc, char **argv) {
    std::cout << std::setprecision(17);
    for (int i = 1; i + 1 < argc; i += 2) {
        std::cout << find_root(std::stod(argv[i]), std::stod(argv[i + 1])) << "\n";
    }
}
'''
    with open("/tmp/root_probe.cpp", "w") as f:
        f.write(probe_source)
    subprocess.run([
        "g++", "-std=c++11", "-I" + REPO, "/tmp/root_probe.cpp",
        os.path.join(REPO, "math_utils.cpp"), "-o", "/tmp/root_probe"
    ], check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    rng = random.SystemRandom()
    cases = [(3.0, 1e-3), (1.5, 1e-5)]
    for _ in range(6):
        cases.append((rng.uniform(1.25, 4.5), 10.0 ** rng.uniform(-8.5, -2.5)))

    args = ["/tmp/root_probe"]
    for x0, tolerance in cases:
        args.extend([repr(x0), repr(tolerance)])
    result = subprocess.run(args, check=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, timeout=10)
    lines = result.stdout.splitlines()
    assert len(lines) == len(cases)
    for line, (x0, tolerance) in zip(lines, cases):
        actual = float(line)
        expected = reference_root(x0, tolerance)
        assert math.isclose(actual, expected, rel_tol=1e-13, abs_tol=1e-13), \
            f"find_root({x0}, {tolerance}) returned {actual}, expected {expected}"


def test_server_running_and_correct():
    # Preserve the original live checks.
    try:
        response = request(b"3.0\n")
        assert response == "2.09455\n", f"Expected '2.09455\\n', got {repr(response)}"
    except ConnectionRefusedError:
        pytest.fail(f"Could not connect to server at {HOST}:{PORT}. Is it running?")
    except socket.timeout:
        pytest.fail("Server connection timed out.")

    try:
        response = request(b"0.0\n")
        assert response == "2.09455\n", f"Expected '2.09455\\n', got {repr(response)}"
    except ConnectionRefusedError:
        pytest.fail(f"Could not connect to server at {HOST}:{PORT} for second test.")
    except socket.timeout:
        pytest.fail("Server connection timed out on second test.")


def test_server_on_derived_random_inputs_and_nonfinite_value():
    rng = random.SystemRandom()
    for _ in range(8):
        x0 = rng.uniform(1.2, 5.0)
        expected = f"{reference_root(x0, 1e-6):.5f}\n"
        response = request((repr(x0) + "\n").encode("ascii"))
        assert response == expected, f"For x0={x0}, expected {expected!r}, got {response!r}"

    # With the specified Newton loop, NaN fails the convergence comparison and is
    # returned as NaN. An unconditional finite root response therefore cannot pass.
    response = request(b"nan\n")
    assert response.endswith("\n"), "Response is not newline terminated"
    assert math.isnan(float(response.strip())), \
        f"Expected Newton handling of NaN, got {response!r}"
    assert SERVER_PROCESS.poll() is None, "Server stopped while handling requests"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
