#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import signal
import subprocess
import time
import urllib.parse
import urllib.request

import pytest

PROJECT = "/home/user/project"
BINARY = os.path.join(PROJECT, "safehashed")
LIBRARY = os.path.join(PROJECT, "libchecksum.so")


@pytest.fixture(scope="session", autouse=True)
def build_and_validate_artifacts():
    subprocess.run(["pkill", "-x", "safehashed"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    for path in (BINARY, LIBRARY):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(["make", "-B"], cwd=PROJECT, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=120)
    assert result.returncode == 0, f"make failed:\n{result.stdout}"

    assert os.path.isfile(BINARY), f"Executable {BINARY} does not exist. Did the build succeed?"
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."
    assert os.path.isfile(LIBRARY), f"Shared library {LIBRARY} does not exist. Did the build succeed?"

    elf = subprocess.run(["readelf", "-h", LIBRARY], text=True,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert elf.returncode == 0 and "DYN (Shared object file)" in elf.stdout, \
        f"{LIBRARY} is not an ELF shared object:\n{elf.stdout}"

    symbols = subprocess.run(["nm", "-D", "--defined-only", LIBRARY], text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert symbols.returncode == 0, symbols.stdout
    exported = [line.split()[-1] for line in symbols.stdout.splitlines() if line.split()]
    assert "calculate_checksum" in exported, \
        f"calculate_checksum is not exported with its unmangled C ABI:\n{symbols.stdout}"

    lib = ctypes.CDLL(LIBRARY)
    calculate = lib.calculate_checksum
    calculate.argtypes = [ctypes.c_char_p]
    calculate.restype = ctypes.c_int
    rng = random.SystemRandom()
    samples = [b"", b"SafeHashed", b"abc", os.urandom(32).hex().encode()]
    samples.append("".join(chr(rng.randrange(32, 127)) for _ in range(41)).encode())
    for sample in samples:
        expected = sum(sample) % 256
        assert calculate(sample) == expected, \
            f"calculate_checksum returned the wrong result for {sample!r}"

    imported = subprocess.run(["nm", "-D", BINARY], text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert imported.returncode == 0 and "dlopen" in imported.stdout, \
        "safehashed does not use the dynamic-loader API"
    with open(BINARY, "rb") as f:
        assert b"libchecksum.so" in f.read(), "safehashed does not reference libchecksum.so"

    hidden = LIBRARY + ".verifier-hidden"
    os.replace(LIBRARY, hidden)
    try:
        try:
            without_library = subprocess.run([BINARY], cwd=PROJECT, text=True,
                                             stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                             timeout=3)
        except subprocess.TimeoutExpired:
            pytest.fail("safehashed kept running without libchecksum.so; it is not loading the required library")
        assert without_library.returncode != 0, \
            "safehashed unexpectedly started without libchecksum.so"
    finally:
        os.replace(hidden, LIBRARY)

    proc = subprocess.Popen([BINARY], cwd=PROJECT, start_new_session=True,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 10
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"safehashed exited before serving requests (status {proc.returncode})")
        try:
            with urllib.request.urlopen("http://127.0.0.1:8080/diff?list_a=1&list_b=2", timeout=0.5) as response:
                if response.status == 200:
                    break
        except Exception:
            time.sleep(0.1)
    else:
        os.killpg(proc.pid, signal.SIGKILL)
        pytest.fail("safehashed did not begin listening on 127.0.0.1:8080")

    return proc


def request_diff(list_a, list_b):
    query = urllib.parse.urlencode({
        "list_a": ",".join(map(str, list_a)),
        "list_b": ",".join(map(str, list_b)),
    })
    with urllib.request.urlopen(f"http://127.0.0.1:8080/diff?{query}", timeout=3) as response:
        body = response.read().decode("utf-8")
        assert response.status == 200
        assert response.headers.get_content_type() == "application/json"
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        pytest.fail(f"API returned invalid JSON: {body!r}")


def test_api_test_log_content():
    log_path = "/home/user/api_test.log"
    assert os.path.isfile(log_path), f"{log_path} does not exist. Did you save the curl output?"

    with open(log_path, "r") as f:
        content = f.read().strip()

    try:
        parsed_content = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail(f"Content of {log_path} is not valid JSON: {content}")

    expected = [15, 23, 99]
    assert parsed_content == expected, f"Expected {expected} in {log_path}, but got {parsed_content}"


def test_safehashed_binary_exists():
    assert os.path.isfile(BINARY), f"Executable {BINARY} does not exist. Did the build succeed?"
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."


def test_libchecksum_so_exists():
    assert os.path.isfile(LIBRARY), f"Shared library {LIBRARY} does not exist. Did the build succeed?"


def test_live_diff_api_fixed_case():
    assert request_diff([99, 15, 42, 8, 23], [42, 8, 100]) == [15, 23, 99]


def test_live_diff_api_derived_cases():
    rng = random.SystemRandom()
    for _ in range(8):
        universe = rng.sample(range(-1000000, 1000001), 24)
        list_a = universe[:15]
        rng.shuffle(list_a)
        list_b = universe[8:20]
        rng.shuffle(list_b)
        expected = sorted(set(list_a) - set(list_b))
        assert request_diff(list_a, list_b) == expected
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
