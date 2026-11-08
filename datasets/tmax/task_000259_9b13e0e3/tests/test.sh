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
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import importlib.util
import json
import math
import os
import random
import re
import subprocess
import time

import pytest
import requests

APP = "/app"
PATCH = "/app/makefile.patch"
MAKEFILE = "/app/tinymath/Makefile"
LIBRARY = "/app/tinymath/libtinymath.so"
SERVER = "/app/server.py"
URL = "http://127.0.0.1:8080/evaluate"


def test_makefile_patch_exists():
    assert os.path.isfile(PATCH), f"Patch file {PATCH} does not exist."
    with open(PATCH, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original assertion.
    assert "-lm" in content or "+lm" in content or "lm" in content, \
        "The patch file does not seem to add the -lm flag."

    # It must be a unified diff which actually adds -lm, not merely prose.
    assert re.search(r"^---\s+\S+", content, re.MULTILINE), "Patch lacks a unified-diff --- header."
    assert re.search(r"^\+\+\+\s+\S+", content, re.MULTILINE), "Patch lacks a unified-diff +++ header."
    assert re.search(r"^@@\s", content, re.MULTILINE), "Patch lacks a unified-diff hunk."
    assert any(line.startswith("+") and not line.startswith("+++") and
               re.search(r"(?<!\S)-lm(?:\s|$)", line)
               for line in content.splitlines()), "Patch does not add the -lm linker flag."


def test_makefile_and_shared_library_are_rebuilt_and_linked():
    assert os.path.isfile(MAKEFILE), f"Makefile {MAKEFILE} does not exist."
    with open(MAKEFILE, "r", encoding="utf-8") as f:
        makefile = f.read()
    assert re.search(r"(?<!\S)-lm(?:\s|$)", makefile, re.MULTILINE), \
        "The actual Makefile does not contain the -lm linker flag."

    # Rebuild from scratch so the library left by setup cannot satisfy the test.
    clean = subprocess.run(["make", "clean"], cwd="/app/tinymath", text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}"
    build = subprocess.run(["make"], cwd="/app/tinymath", text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert build.returncode == 0, f"Clean library build failed:\n{build.stdout}"

    # Preserve the original existence assertion.
    assert os.path.isfile(LIBRARY), f"Shared library {LIBRARY} was not compiled."
    with open(LIBRARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "libtinymath.so is not an ELF binary."

    dynamic = subprocess.check_output(["readelf", "-d", LIBRARY], text=True,
                                      stderr=subprocess.STDOUT)
    assert re.search(r"NEEDED.*libm\.so", dynamic), \
        "libtinymath.so has no dynamic dependency on libm; -lm was not linked correctly."

    # Execute the freshly built artifact directly with independently selected inputs.
    lib = ctypes.CDLL(LIBRARY, mode=getattr(os, "RTLD_NOW", ctypes.DEFAULT_MODE))
    lib.evaluate.restype = ctypes.c_double
    lib.evaluate.argtypes = [ctypes.c_char_p]
    for expression, expected in [
        ("sin(0.371) + 8.25", math.sin(0.371) + 8.25),
        ("cos(1.127) * -3.5", math.cos(1.127) * -3.5),
        ("sin(-0.83) - 2.125", math.sin(-0.83) - 2.125),
    ]:
        actual = lib.evaluate(expression.encode("utf-8"))
        assert math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-9), \
            f"C library evaluated {expression!r} as {actual}, expected {expected}"


def load_server_module():
    spec = importlib.util.spec_from_file_location("submitted_server", SERVER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FakeGetVersion:
    def __init__(self, version):
        self.version = version.encode("utf-8")
        self.restype = None

    def __call__(self):
        return self.version


class FakeLibrary:
    def __init__(self, version):
        self.get_version = FakeGetVersion(version)


def test_semantic_version_comparison():
    assert os.path.isfile(SERVER), f"Server file {SERVER} does not exist."
    server = load_server_module()
    assert hasattr(server, "check_version"), "server.py has no check_version function."

    # Independently exercise both sides of the required >= 1.2.0 comparison.
    cases = {
        "0.99.99": False,
        "1.1.9": False,
        "1.2.0": True,
        "1.2.1": True,
        "1.10.0": True,
        "2.0.0": True,
        "10.0.0": True,
    }
    for version, expected in cases.items():
        actual = server.check_version(FakeLibrary(version))
        assert actual is expected, \
            f"check_version({version!r}) returned {actual!r}; expected {expected!r}"

    # Also execute the check against the real rebuilt library.
    real_lib = ctypes.CDLL(LIBRARY)
    assert server.check_version(real_lib) is True, \
        "server.py rejects the rebuilt library's version."


def listener_is_server_py():
    wanted_inode = None
    with open("/proc/net/tcp", "r", encoding="utf-8") as f:
        for line in f.readlines()[1:]:
            fields = line.split()
            if fields[1].upper() == "0100007F:1F90" and fields[3] == "0A":
                wanted_inode = fields[9]
                break
    if not wanted_inode:
        return False

    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            owns_socket = any(os.readlink(os.path.join(fd_dir, fd)) == f"socket:[{wanted_inode}]"
                              for fd in os.listdir(fd_dir))
            if not owns_socket:
                continue
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
            if "server.py" in cmdline and "python" in cmdline.lower():
                return True
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return False


def post_and_check(expression, expected):
    response = requests.post(URL, json={"expression": expression}, timeout=5)
    assert response.status_code == 200, \
        f"Expected status 200, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "result" in data, "Response JSON missing 'result' key."
    assert isinstance(data["result"], (int, float)), "Response result is not numeric."
    assert math.isclose(data["result"], expected, rel_tol=1e-7, abs_tol=1e-7), \
        f"For {expression!r}, expected {expected}, got {data['result']}"


def test_server_evaluate_endpoint():
    # Preserve the original readiness behavior and fixed endpoint assertions.
    for _ in range(5):
        try:
            requests.get("http://127.0.0.1:8080/", timeout=1)
            break
        except requests.exceptions.ConnectionError:
            time.sleep(1)

    try:
        post_and_check("cos(0) * 5", 5.0)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the server at 127.0.0.1:8080. Is it running?")
    post_and_check("sin(3.14159265359) + 42", math.sin(3.14159265359) + 42)

    assert listener_is_server_py(), \
        "The process listening on 127.0.0.1:8080 is not the requested Python server.py service."

    # Use unpredictable expressions so fixed canned responses cannot pass.
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    for _ in range(8):
        angle = rng.uniform(-2.5, 2.5)
        operand = rng.uniform(-20.0, 20.0)
        function = rng.choice(["sin", "cos"])
        operator = rng.choice(["+", "-", "*"])
        base = math.sin(angle) if function == "sin" else math.cos(angle)
        expected = {"+": base + operand, "-": base - operand, "*": base * operand}[operator]
        expression = f"{function}({angle:.12f}) {operator} {operand:.12f}"
        # Compute from the rounded values actually sent.
        sent_angle = float(f"{angle:.12f}")
        sent_operand = float(f"{operand:.12f}")
        sent_base = math.sin(sent_angle) if function == "sin" else math.cos(sent_angle)
        expected = {"+": sent_base + sent_operand,
                    "-": sent_base - sent_operand,
                    "*": sent_base * sent_operand}[operator]
        post_and_check(expression, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
