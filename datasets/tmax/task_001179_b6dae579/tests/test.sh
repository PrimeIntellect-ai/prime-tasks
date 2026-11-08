#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import signal
import socket
import struct
import subprocess
import tempfile
import time
from pathlib import Path

import pytest
import requests
from PIL import Image, ImageDraw, ImageFont

BASE_URL = "http://127.0.0.1:8080"
SOURCE = Path("/home/user/evaluator.c")
START = Path("/home/user/start.sh")
IMAGE = Path("/app/equation.png")
_rng = random.SystemRandom()
_started_processes = []


def wait_for_service(timeout=60):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            requests.get(BASE_URL, timeout=1)
            return True
        except requests.RequestException:
            time.sleep(0.25)
    return False


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) >= 10 and fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                inodes.add(fields[9])

    pids = set()
    if not inodes:
        return pids
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(proc.name))
                    break
        except OSError:
            pass
    return pids


def stop_service():
    pids = listener_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 4
    while time.time() < deadline and listener_pids():
        time.sleep(0.1)
    for pid in listener_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listener_pids():
        time.sleep(0.1)
    assert not listener_pids(), "Could not stop the existing service on port 8080"


def launch_service(log_name):
    log = open(f"/tmp/{log_name}", "ab", buffering=0)
    proc = subprocess.Popen(
        ["bash", str(START)],
        cwd="/home/user",
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    _started_processes.append((proc, log))
    assert wait_for_service(), f"Service did not start; see /tmp/{log_name}"
    return proc


def find_shared_libraries():
    found = []
    for root in (Path("/home/user"), Path("/app")):
        if root.exists():
            found.extend(root.rglob("libevaluator.so"))
    return [p.resolve() for p in found if p.is_file()]


def assert_real_shared_library_is_loaded():
    libraries = find_shared_libraries()
    assert libraries, "start.sh did not produce libevaluator.so"
    valid = []
    for library in libraries:
        data = library.read_bytes()[:20]
        if len(data) >= 18 and data[:4] == b"\x7fELF":
            endian = "<" if data[5] == 1 else ">"
            if struct.unpack(endian + "H", data[16:18])[0] == 3:  # ET_DYN
                valid.append(library)
    assert valid, "libevaluator.so is not an ELF shared object"

    mapped = False
    for pid in listener_pids():
        try:
            maps = Path(f"/proc/{pid}/maps").read_text(errors="replace")
        except OSError:
            continue
        if "libevaluator.so" in maps:
            mapped = True
            break
    assert mapped, "The process serving port 8080 has not loaded libevaluator.so"


def post_expression(expression, timeout=8):
    response = requests.post(
        f"{BASE_URL}/evaluate", json={"expression": expression}, timeout=timeout
    )
    assert response.status_code == 200, (
        f"Expected status 200, got {response.status_code}. Response: {response.text}"
    )
    data = response.json()
    assert "result" in data, "Response JSON missing 'result' key"
    assert type(data["result"]) is int, "result must be a JSON integer"
    return data["result"]


def make_cases():
    cases = []
    for _ in range(18):
        count = _rng.randint(4, 35)
        stack = [(str(_rng.randint(1, 20)), None) for _ in range(count)]
        stack = [(text, int(text)) for text, _ in stack]
        while len(stack) > 1:
            index = _rng.randrange(len(stack) - 1)
            left_text, left_value = stack.pop(index)
            right_text, right_value = stack.pop(index)
            if _rng.random() < 0.45 and left_value * right_value <= 100000000:
                op = "*"
                value = left_value * right_value
            else:
                op = "+"
                value = left_value + right_value
            stack.insert(index, (f"{left_text} {right_text} {op}", value))
        cases.append(stack[0])

    # 1,000 operands plus 999 operators: 1,999 tokens and a maximum stack depth
    # of 1,000, exercising the stated large-input requirement.
    values = [_rng.randint(1, 9) for _ in range(1000)]
    tokens = [str(v) for v in values]
    result = values[0]
    for value in values[1:]:
        if _rng.random() < 0.12:
            tokens.append("1")
            tokens.append("*")
        else:
            tokens.append(str(value))
            tokens.append("+")
            result += value
    # The construction above contains one initial token and two tokens per step.
    cases.append((" ".join(tokens), result))
    return cases


DYNAMIC_CASES = make_cases()


def test_c_evaluator_directly_with_sanitizers():
    assert SOURCE.is_file(), "/home/user/evaluator.c is missing"
    driver = Path("/tmp/evaluator_driver.c")
    binary = Path("/tmp/evaluator_driver")
    driver.write_text(r'''#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
int evaluate_rpn(const char *expr);
int main(int argc, char **argv) {
    if (argc != 3) return 2;
    errno = 0;
    long expected = strtol(argv[2], NULL, 10);
    if (errno) return 3;
    int actual = evaluate_rpn(argv[1]);
    if (actual != (int)expected) {
        fprintf(stderr, "expected %ld, got %d\n", expected, actual);
        return 1;
    }
    return 0;
}
''')
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O1", "-g", "-fno-omit-frame-pointer",
         "-fsanitize=address,undefined", str(SOURCE), str(driver), "-o", str(binary)],
        text=True, capture_output=True, timeout=30
    )
    assert compile_result.returncode == 0, compile_result.stdout + compile_result.stderr
    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1:abort_on_error=1"
    env["UBSAN_OPTIONS"] = "halt_on_error=1:print_stacktrace=1"
    for expression, expected in DYNAMIC_CASES:
        run = subprocess.run(
            [str(binary), expression, str(expected)], env=env,
            text=True, capture_output=True, timeout=10
        )
        assert run.returncode == 0, run.stdout + run.stderr


@pytest.fixture(scope="session", autouse=True)
def verify_build_and_startup_integration():
    assert SOURCE.is_file(), "/home/user/evaluator.c is missing"
    assert START.is_file(), "/home/user/start.sh is missing"
    original_source = SOURCE.read_bytes()
    marker = _rng.randint(1200000000, 1900000000)
    probe_expression = f"{_rng.randint(21, 99)} {_rng.randint(2, 9)} +"

    stop_service()
    try:
        SOURCE.write_text(
            "#include <stddef.h>\n"
            f"int evaluate_rpn(const char *expr) {{ (void)expr; return {marker}; }}\n"
        )
        sentinel_proc = launch_service("sentinel_start.log")
        assert_real_shared_library_is_loaded()
        assert post_expression(probe_expression) == marker, (
            "The HTTP endpoint did not use the C evaluate_rpn implementation built by start.sh"
        )
    finally:
        stop_service()
        SOURCE.write_bytes(original_source)
        if 'sentinel_proc' in locals() and sentinel_proc.poll() is None:
            try:
                os.killpg(sentinel_proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

    launch_service("normal_start.log")
    assert_real_shared_library_is_loaded()
    yield


def test_evaluate_simple():
    payload = {"expression": "10 20 + 30 *"}
    try:
        response = requests.post(f"{BASE_URL}/evaluate", json=payload, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect or request timed out: {e}")
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "result" in data, "Response JSON missing 'result' key"
    assert data["result"] == 900, f"Expected result 900, got {data['result']}"


def test_evaluate_large():
    expression = " ".join(["1"] * 1000 + ["+"] * 999)
    payload = {"expression": expression}
    try:
        response = requests.post(f"{BASE_URL}/evaluate", json=payload, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect or request timed out: {e}")
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "result" in data, "Response JSON missing 'result' key"
    assert data["result"] == 1000, f"Expected result 1000, got {data['result']}"


def test_randomized_http_evaluation():
    for expression, expected in DYNAMIC_CASES[:10] + DYNAMIC_CASES[-1:]:
        assert post_expression(expression, timeout=10) == expected


def test_evaluate_image():
    try:
        response = requests.get(f"{BASE_URL}/image", timeout=10)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect or request timed out: {e}")
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "result" in data, "Response JSON missing 'result' key"
    assert data["result"] == 80, f"Expected result 80, got {data['result']}"


def test_image_is_actually_read_and_ocr_evaluated():
    original = IMAGE.read_bytes()
    a = _rng.randint(21, 89)
    b = _rng.randint(2, 9)
    c = _rng.randint(2, 7)
    expression = f"{a} {b} + {c} *"
    expected = (a + b) * c
    try:
        image = Image.new("RGB", (600, 110), "white")
        draw = ImageDraw.Draw(image)
        font = ImageFont.truetype(
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 40
        )
        draw.text((20, 20), expression, fill="black", font=font)
        image.save(IMAGE)
        response = requests.get(f"{BASE_URL}/image?nonce={_rng.getrandbits(64)}", timeout=15)
        assert response.status_code == 200, response.text
        data = response.json()
        assert "result" in data
        assert data["result"] == expected, (
            f"OCR image contained {expression!r}; expected {expected}, got {data['result']}"
        )
    finally:
        IMAGE.write_bytes(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
