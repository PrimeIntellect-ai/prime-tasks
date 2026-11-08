#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import os
import random
import re
import subprocess

import pytest

BASE_DIR = "/home/user/polyglot_system"
BUILD_SH = os.path.join(BASE_DIR, "build.sh")
VERIFY_PY = os.path.join(BASE_DIR, "verify.py")
SO_PATH = os.path.join(BASE_DIR, "lib/librust_encoder.so")
BIN_PATH = os.path.join(BASE_DIR, "bin/go_encoder")
LOG_PATH = os.path.join(BASE_DIR, "test_results.log")


def test_00_run_build_and_verification_scripts():
    assert os.path.isfile(BUILD_SH), f"Build script {BUILD_SH} is missing."
    assert os.path.isfile(VERIFY_PY), f"Verification script {VERIFY_PY} is missing."

    for path in (SO_PATH, BIN_PATH, LOG_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["PATH"] = "/opt/rust/bin:" + env.get("PATH", "")
    build = subprocess.run(
        ["bash", BUILD_SH], cwd=BASE_DIR, env=env,
        capture_output=True, text=True, timeout=180
    )
    assert build.returncode == 0, f"build.sh failed:\nSTDOUT:\n{build.stdout}\nSTDERR:\n{build.stderr}"
    assert os.path.isfile(SO_PATH), "build.sh did not create the Rust shared object."
    assert os.path.isfile(BIN_PATH), "build.sh did not create the Go executable."
    assert os.access(BIN_PATH, os.X_OK), "The freshly built Go artifact is not executable."

    # Wrap the freshly built Go binary while verify.py runs. This confirms that
    # the property test really invokes the required executable on varied inputs.
    real_bin = "/tmp/go_encoder.real"
    calls_log = "/tmp/verify_go_calls.jsonl"
    for path in (real_bin, calls_log):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    os.replace(BIN_PATH, real_bin)
    wrapper = f'''#!/usr/bin/python3
import json, os, sys
with open({calls_log!r}, "a", encoding="utf-8") as f:
    f.write(json.dumps(sys.argv[1:], ensure_ascii=True) + "\\n")
os.execv({real_bin!r}, [{real_bin!r}] + sys.argv[1:])
'''
    with open(BIN_PATH, "w", encoding="utf-8") as f:
        f.write(wrapper)
    os.chmod(BIN_PATH, 0o755)

    try:
        verify = subprocess.run(
            ["python3", VERIFY_PY], cwd=BASE_DIR, env=env,
            capture_output=True, text=True, timeout=180
        )
    finally:
        try:
            os.remove(BIN_PATH)
        except FileNotFoundError:
            pass
        if os.path.exists(real_bin):
            os.replace(real_bin, BIN_PATH)

    assert verify.returncode == 0, f"verify.py failed:\nSTDOUT:\n{verify.stdout}\nSTDERR:\n{verify.stderr}"
    assert os.path.isfile(calls_log), "verify.py never invoked the Go executable."
    with open(calls_log, encoding="utf-8") as f:
        calls = [json.loads(line) for line in f if line.strip()]
    tested_inputs = {args[0] for args in calls if len(args) == 1}
    assert len(tested_inputs) >= 5, "verify.py did not exercise the Go executable on varied property-test inputs."

    assert os.path.isfile(LOG_PATH), "verify.py did not create test_results.log."
    with open(LOG_PATH, encoding="utf-8") as f:
        assert f.read() == "PROPERTY_TESTS_PASSED", "verify.py did not write the exact required success marker."


def test_test_results_log():
    log_path = os.path.join(BASE_DIR, "test_results.log")
    assert os.path.isfile(log_path), f"Log file {log_path} is missing."

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert "PROPERTY_TESTS_PASSED" in content, f"Expected 'PROPERTY_TESTS_PASSED' in {log_path}, found {content!r}"


def test_rust_code_fixed():
    lib_rs_path = os.path.join(BASE_DIR, "rust_encoder/src/lib.rs")
    assert os.path.isfile(lib_rs_path), f"Rust source {lib_rs_path} is missing."

    with open(lib_rs_path, "r") as f:
        content = f.read()

    assert "no_mangle" in content, "Rust code is missing #[no_mangle] attribute."
    assert "extern \"C\"" in content, "Rust code is missing extern \"C\"."


def test_build_artifacts_exist():
    so_path = os.path.join(BASE_DIR, "lib/librust_encoder.so")
    bin_path = os.path.join(BASE_DIR, "bin/go_encoder")

    assert os.path.isfile(so_path), f"Rust shared object {so_path} is missing."
    assert os.path.isfile(bin_path), f"Go executable {bin_path} is missing."
    assert os.access(bin_path, os.X_OK), f"Go executable {bin_path} is not executable."


def test_go_encoder_execution():
    bin_path = os.path.join(BASE_DIR, "bin/go_encoder")
    assert os.path.isfile(bin_path), "Go executable not found."

    test_str = "hello"
    expected_hex = test_str.encode('utf-8').hex()

    try:
        result = subprocess.run([bin_path, test_str], capture_output=True, text=True, timeout=2)
        assert result.returncode == 0, f"Go executable failed with return code {result.returncode}"
        out = result.stdout.strip()
        assert len(out) == len(expected_hex), "Go executable output length mismatch."
    except subprocess.TimeoutExpired:
        pytest.fail("Go executable timed out, indicating a deadlock is still present.")


def test_go_encoder_exact_behavior_on_varied_inputs():
    rng = random.SystemRandom()
    alphabet = list("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 !@#$%^&*()-_=+") + ["é", "漢", "🙂", "Ω"]
    cases = [
        "a", "hello", "test string", "é", "漢字", "🙂go🙂", "a b c", "x" * 100,
    ]
    cases.extend("".join(rng.choice(alphabet) for _ in range(rng.randint(1, 80))) for _ in range(16))

    for value in cases:
        expected = value.encode("utf-8").hex()
        try:
            result = subprocess.run([BIN_PATH, value], capture_output=True, text=True, timeout=3)
        except subprocess.TimeoutExpired:
            pytest.fail(f"Go executable deadlocked for input {value!r}")
        assert result.returncode == 0, f"Go executable failed for {value!r}: {result.stderr}"
        assert result.stdout.strip() == expected, f"Go output was incorrect for {value!r}"


def test_rust_library_execution():
    so_path = os.path.join(BASE_DIR, "lib/librust_encoder.so")
    assert os.path.isfile(so_path), "Rust shared object not found."

    try:
        lib = ctypes.CDLL(so_path)
    except OSError as e:
        pytest.fail(f"Failed to load Rust shared object: {e}")

    assert hasattr(lib, "encode_hex"), "encode_hex function not found in shared object. Was #[no_mangle] used?"

    encode_hex = lib.encode_hex
    encode_hex.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    encode_hex.restype = None

    input_str = b"test string"
    expected_hex = input_str.hex().encode('utf-8')
    output_buf = ctypes.create_string_buffer(512)

    encode_hex(input_str, output_buf)

    assert output_buf.value == expected_hex, f"Rust encode_hex produced incorrect output: {output_buf.value} != {expected_hex}"


def test_rust_library_exact_behavior_on_varied_inputs():
    lib = ctypes.CDLL(SO_PATH)
    assert hasattr(lib, "encode_hex"), "encode_hex symbol is absent."
    encode_hex = lib.encode_hex
    encode_hex.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    encode_hex.restype = None

    rng = random.SystemRandom()
    alphabet = list("abcdefXYZ0123456789 -_!?") + ["é", "漢", "🙂", "Ω"]
    cases = ["a", "hello", "é", "漢字", "🙂go🙂", "x" * 100]
    cases.extend("".join(rng.choice(alphabet) for _ in range(rng.randint(1, 60))) for _ in range(16))
    for value in cases:
        raw = value.encode("utf-8")
        expected = raw.hex().encode("ascii")
        output = ctypes.create_string_buffer(max(512, len(expected) + 1))
        encode_hex(raw, output)
        assert output.value == expected, f"Rust output was incorrect for {value!r}"


def test_build_script_exists():
    build_sh_path = os.path.join(BASE_DIR, "build.sh")
    assert os.path.isfile(build_sh_path), f"Build script {build_sh_path} is missing."


def test_verify_script_exists():
    verify_py_path = os.path.join(BASE_DIR, "verify.py")
    assert os.path.isfile(verify_py_path), f"Verification script {verify_py_path} is missing."


def test_verify_script_contains_required_property_test():
    with open(VERIFY_PY, encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source)

    text_calls = []
    has_given = False
    has_assertion = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            name = node.func.attr if isinstance(node.func, ast.Attribute) else node.func.id if isinstance(node.func, ast.Name) else ""
            if name == "text":
                text_calls.append(node)
            if name == "given":
                has_given = True
            if name.startswith("assert"):
                has_assertion = True
        elif isinstance(node, ast.Assert):
            has_assertion = True

    def required_bounds(call):
        values = {kw.arg: kw.value.value for kw in call.keywords if kw.arg and isinstance(kw.value, ast.Constant)}
        return values.get("min_size") == 1 and values.get("max_size") == 100

    assert "hypothesis" in source, "verify.py does not import/use Hypothesis."
    assert has_given, "verify.py does not run a Hypothesis @given property test."
    assert any(required_bounds(call) for call in text_calls), "verify.py must use text(min_size=1, max_size=100)."
    assert "subprocess" in source, "verify.py does not use subprocess for the Go executable."
    assert "ctypes" in source, "verify.py does not use ctypes for the Rust library."
    assert has_assertion, "verify.py contains no assertion comparing results."
    assert "PROPERTY_TESTS_PASSED" in source, "verify.py does not contain the required success marker."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
