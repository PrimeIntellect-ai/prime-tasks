#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import math
import os
import random
import re
import secrets
import subprocess
import tempfile

import pytest

EXECUTABLE = "/home/user/src/validator"
SOURCE = "/home/user/src/validator.cpp"
PREFIX = "/home/user/local"


def run_validator(executable, path):
    return subprocess.run(
        [executable, path],
        capture_output=True,
        text=True,
        timeout=2,
    )


def assert_answer(executable, path, expected):
    try:
        result = run_validator(executable, path)
    except subprocess.TimeoutExpired:
        pytest.fail(f"Validator timed out on {os.path.basename(path)}")
    assert result.returncode == 0, f"Nonzero exit on {os.path.basename(path)}: {result.returncode}"
    assert result.stdout == expected + "\n", (
        f"Wrong output on {os.path.basename(path)}: expected {expected!r}, got {result.stdout!r}"
    )


def test_validator_executable_exists():
    assert os.path.exists(EXECUTABLE), f"Executable not found at {EXECUTABLE}"
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is not a file"
    assert os.access(EXECUTABLE, os.X_OK), f"File at {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "validator must be a compiled executable"


def test_validator_behavior_on_corpora():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"Missing clean corpus directory: {clean_dir}"
    assert os.path.isdir(evil_dir), f"Missing evil corpus directory: {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    assert len(clean_files) > 0, "No files found in clean corpus"
    assert len(evil_files) > 0, "No files found in evil corpus"

    clean_failures = []
    evil_failures = []

    for file_path in clean_files:
        try:
            result = run_validator(EXECUTABLE, file_path)
            if result.stdout != "ACCEPT\n" or result.returncode != 0:
                clean_failures.append(os.path.basename(file_path))
        except subprocess.TimeoutExpired:
            clean_failures.append(f"{os.path.basename(file_path)} (timeout)")
        except Exception as e:
            clean_failures.append(f"{os.path.basename(file_path)} (error: {e})")

    for file_path in evil_files:
        try:
            result = run_validator(EXECUTABLE, file_path)
            if result.stdout != "REJECT\n" or result.returncode != 0:
                evil_failures.append(os.path.basename(file_path))
        except subprocess.TimeoutExpired:
            evil_failures.append(f"{os.path.basename(file_path)} (timeout)")
        except Exception as e:
            evil_failures.append(f"{os.path.basename(file_path)} (error: {e})")

    error_messages = []
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}")
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed/accepted: {', '.join(evil_failures)}")
    if error_messages:
        pytest.fail(" | ".join(error_messages))


def oracle(raw):
    try:
        obj = json.loads(raw, parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))
    except Exception:
        return "REJECT"
    if not isinstance(obj, dict) or obj.get("status") != "success" or "data" not in obj:
        return "REJECT"
    data = obj["data"]
    if not isinstance(data, list) or len(data) != 256:
        return "REJECT"
    for value in data:
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return "REJECT"
        if not math.isfinite(value) or value < -10.0 or value > 10.0:
            return "REJECT"
    return "ACCEPT"


def make_generated_cases():
    rng = random.Random(secrets.randbits(128))
    valid = [rng.uniform(-9.999, 9.999) for _ in range(256)]
    cases = [
        json.dumps({"status": "success", "data": valid}),
        json.dumps({"data": [-10.0, 10.0] + [0.0] * 254, "status": "success", "extra": {"ignored": True}}, separators=(",", ":")),
        '{"stat\\u0075s":"succ\\u0065ss","data":[' + ','.join(['1e0'] * 256) + ']}',
        json.dumps({"status": "failure", "data": [0.0] * 256}),
        json.dumps({"status": "success", "data": [0.0] * 255}),
        json.dumps({"status": "success", "data": [0.0] * 257}),
        json.dumps({"status": "success", "data": [0.0] * 255 + [10.000001]}),
        json.dumps({"status": "success", "data": [0.0] * 255 + [-10.000001]}),
        json.dumps({"status": "success", "data": [0.0] * 255 + [True]}),
        json.dumps({"status": "success", "data": [0.0] * 255 + ["1.0"]}),
        json.dumps({"status": "success", "data": [[0.0] * 256]}),
        json.dumps({"status": "success", "data": [0.0] * 255 + [None]}),
        json.dumps({"data": [0.0] * 256}),
        json.dumps({"status": "success"}),
        json.dumps(["success", [0.0] * 256]),
        '{"status":"success","data":[' + ','.join(['0'] * 255) + ',NaN]}',
        '{"status":"success","data":[' + ','.join(['0'] * 255) + ',Infinity]}',
        '{"status":"success","data":[' + ','.join(['0'] * 255) + ',1e400]}',
        '{"status":"success","data":[1,2,3',
        '{"status":"success","data":[' + ','.join(['0'] * 256) + '],}',
    ]

    for _ in range(20):
        data = [rng.uniform(-10.0, 10.0) for _ in range(256)]
        obj = {"status": "success", "data": data}
        mutation = rng.randrange(7)
        if mutation == 1:
            obj["status"] = rng.choice(["error", "Success", "", None])
        elif mutation == 2:
            obj["data"] = data[:rng.choice([0, 1, 254, 255])]
        elif mutation == 3:
            obj["data"] = data + [rng.uniform(-10.0, 10.0)]
        elif mutation == 4:
            obj["data"][rng.randrange(256)] = rng.choice([10.1, -10.1, 1000000.0])
        elif mutation == 5:
            obj["data"][rng.randrange(256)] = rng.choice(["0", None, False, {}])
        elif mutation == 6:
            del obj[rng.choice(["status", "data"])]
        cases.append(json.dumps(obj, separators=(",", ":"), sort_keys=bool(rng.randrange(2))))
    return cases


def test_generated_holdout_behavior():
    cases = make_generated_cases()
    assert any(oracle(raw) == "ACCEPT" for raw in cases)
    assert any(oracle(raw) == "REJECT" for raw in cases)

    with tempfile.TemporaryDirectory(prefix="v_", dir="/tmp") as directory:
        for index, raw in enumerate(cases):
            path = os.path.join(directory, secrets.token_hex(8) + f"_{index}.json")
            with open(path, "w", encoding="utf-8") as f:
                f.write(raw)
            assert_answer(EXECUTABLE, path, oracle(raw))


def test_cmake_install_source_and_linkage():
    assert os.path.isfile(SOURCE), f"Missing source file: {SOURCE}"
    assert os.path.isfile("/app/simdjson-3.6.0/CMakeLists.txt")
    cmake_text = open("/app/simdjson-3.6.0/CMakeLists.txt", encoding="utf-8", errors="replace").read()
    assert not re.search(r"CXX_STANDARD\s+11(?:\s|$|\))", cmake_text), "The CMake C++11 perturbation was not fixed"

    header = os.path.join(PREFIX, "include", "simdjson.h")
    assert os.path.isfile(header), f"Installed simdjson header missing: {header}"
    libraries = [p for p in glob.glob(os.path.join(PREFIX, "lib*", "**", "libsimdjson.so*"), recursive=True) if os.path.isfile(p)]
    libraries += [p for p in glob.glob(os.path.join(PREFIX, "lib*", "**", "libsimdjson.a"), recursive=True) if os.path.isfile(p)]
    assert libraries, "No installed simdjson library found under /home/user/local"
    libdirs = sorted(set(os.path.dirname(p) for p in libraries))

    rebuilt = os.path.join(tempfile.gettempdir(), "validator_rebuilt_" + secrets.token_hex(8))
    command = ["g++", "-std=c++17", SOURCE, "-I" + os.path.join(PREFIX, "include")]
    for directory in libdirs:
        command.extend(["-L" + directory, "-Wl,-rpath," + directory])
    command.extend(["-lsimdjson", "-o", rebuilt])
    result = subprocess.run(command, capture_output=True, text=True, timeout=90)
    assert result.returncode == 0, f"validator.cpp does not build against installed simdjson:\n{result.stderr}"

    try:
        symbol_outputs = []
        for target in (EXECUTABLE, rebuilt):
            for args in (["nm", "-C", target], ["nm", "-D", "-C", target], ["ldd", target]):
                inspected = subprocess.run(args, capture_output=True, text=True, timeout=10)
                symbol_outputs.append((target, inspected.stdout + inspected.stderr))
        for target in (EXECUTABLE, rebuilt):
            combined = "\n".join(output for candidate, output in symbol_outputs if candidate == target).lower()
            assert "simdjson" in combined, f"{target} does not appear to link against simdjson"

        cases = make_generated_cases()[:12]
        with tempfile.TemporaryDirectory(prefix="r_", dir="/tmp") as directory:
            for index, raw in enumerate(cases):
                path = os.path.join(directory, secrets.token_hex(8) + f"_{index}.json")
                with open(path, "w", encoding="utf-8") as f:
                    f.write(raw)
                assert_answer(rebuilt, path, oracle(raw))
    finally:
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
