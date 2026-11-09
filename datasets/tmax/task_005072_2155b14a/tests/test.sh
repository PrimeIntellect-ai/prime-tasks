#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import string
import subprocess

import pytest

PROJECT = "/home/user/math_project"
EXECUTABLE = os.path.join(PROJECT, "math_router")
OBJECTS = ["main.o", "encoder.o", "decoder.o"]


def encode_string(data: str, shift: int) -> str:
    """Compute the required modulo-256 uppercase hexadecimal output."""
    return "".join(f"{(ord(c) + shift) % 256:02X}" for c in data)


def run_router(url: str):
    return subprocess.run(
        [EXECUTABLE, url],
        capture_output=True,
        text=True,
        timeout=5,
    )


@pytest.fixture(scope="session", autouse=True)
def rebuild_project():
    clean = subprocess.run(
        ["make", "clean"], cwd=PROJECT, capture_output=True, text=True, timeout=30
    )
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}\n{clean.stderr}"
    assert not os.path.exists(EXECUTABLE), "make clean did not remove math_router"
    for name in OBJECTS:
        assert not os.path.exists(os.path.join(PROJECT, name)), f"make clean did not remove {name}"

    build = subprocess.run(
        ["make"], cwd=PROJECT, capture_output=True, text=True, timeout=30
    )
    assert build.returncode == 0, f"make failed:\n{build.stdout}\n{build.stderr}"

    assert os.path.isfile(EXECUTABLE), "make did not produce math_router"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "math_router is not a compiled ELF executable"

    for name in OBJECTS:
        path = os.path.join(PROJECT, name)
        assert os.path.isfile(path), f"make did not produce required object file {name}"
        with open(path, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"{name} is not a compiled object file"


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable not found at {EXECUTABLE}. Did make run successfully?"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable."


def test_run_log_content():
    log_file = os.path.join(PROJECT, "run.log")
    assert os.path.isfile(log_file), f"Log file not found at {log_file}."

    with open(log_file, "r") as f:
        content = f.read().strip()

    expected_hex = encode_string("AgentTraining", 14)
    assert content == expected_hex, f"run.log content '{content}' does not match expected '{expected_hex}'."


def test_math_router_valid_route():
    test_url = "/api/encode?shift=10&data=abc"
    expected_hex = encode_string("abc", 10)
    result = run_router(test_url)

    assert result.returncode == 0, f"Expected exit code 0 for valid route, got {result.returncode}."
    output = result.stdout.strip()
    assert output == expected_hex, f"Expected output '{expected_hex}', got '{output}'."


def test_math_router_invalid_route():
    test_url = "/api/badroute?shift=1&data=a"
    result = run_router(test_url)

    assert result.returncode == 1, f"Expected exit code 1 for invalid route, got {result.returncode}."
    output = result.stdout.strip()
    assert output == "404 Not Found", f"Expected '404 Not Found' for invalid route, got '{output}'."


def test_randomized_encoding_and_parsing():
    rng = secrets.SystemRandom()
    alphabet = string.ascii_letters + string.digits + "-_.~"
    lengths = [1, 2, 7, 19, 37, 63, 100]
    shifts = [0, 1, 255, 256, 511]

    cases = []
    for length in lengths:
        data = "".join(rng.choice(alphabet) for _ in range(length))
        cases.append((rng.randrange(0, 4097), data))
    for shift in shifts:
        length = rng.randrange(3, 50)
        data = "".join(rng.choice(alphabet) for _ in range(length))
        cases.append((shift, data))

    for shift, data in cases:
        url = f"/api/encode?shift={shift}&data={data}"
        expected = encode_string(data, shift)
        result = run_router(url)
        assert result.returncode == 0, f"Valid URL {url!r} returned {result.returncode}: {result.stderr!r}"
        assert result.stdout.strip() == expected, (
            f"For shift={shift}, data={data!r}, expected {expected!r}, got {result.stdout!r}"
        )


def test_randomized_invalid_routes():
    rng = secrets.SystemRandom()
    suffix = "".join(rng.choice(string.ascii_letters) for _ in range(12))
    routes = [
        f"/api/{suffix}",
        f"/api/encode{suffix}",
        f"/{suffix}/encode",
    ]
    for route in routes:
        result = run_router(f"{route}?shift={rng.randrange(1, 1000)}&data=RandomData")
        assert result.returncode == 1, f"Invalid route {route!r} returned {result.returncode}"
        assert result.stdout.strip() == "404 Not Found", (
            f"Invalid route {route!r} produced {result.stdout!r}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
