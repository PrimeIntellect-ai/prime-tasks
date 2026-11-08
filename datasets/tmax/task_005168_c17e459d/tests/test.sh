#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import importlib.util
import json
import os
import secrets
import shutil
import subprocess
import sys
import tempfile

LIB_PATH = "/home/user/rust_validator/target/release/librust_validator.so"
WRAPPER_PATH = "/home/user/py3_wrapper.py"
MASK = (1 << 64) - 1
PRIME = 11400714819323198485


def legacy_signature(token_id, salt):
    return ((token_id ^ salt) * PRIME) & MASK


def load_wrapper():
    spec = importlib.util.spec_from_file_location("py3_wrapper", WRAPPER_PATH)
    assert spec is not None and spec.loader is not None, "Could not load py3_wrapper.py"
    module = importlib.util.module_from_spec(spec)
    sys.modules["py3_wrapper"] = module
    spec.loader.exec_module(module)
    return module


def test_file_existence():
    """Verify that all required files and directories exist."""
    required_files = [
        "/home/user/rust_validator/Cargo.toml",
        LIB_PATH,
        WRAPPER_PATH,
        "/home/user/test_validator.py",
        "/home/user/test_results.log",
    ]
    for file_path in required_files:
        assert os.path.isfile(file_path), f"Required file missing: {file_path}"


def test_log_file_verification():
    """Verify that the test results log indicates a successful test run."""
    log_path = "/home/user/test_results.log"
    assert os.path.isfile(log_path), f"Log file missing: {log_path}"
    with open(log_path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "passed" in content, "Log file does not indicate a passed test run. Looked for 'passed'."
    assert "failed" not in content.lower() or "0 failed" in content.lower(), "Log file indicates there were failed tests."


def test_cargo_configuration():
    with open("/home/user/rust_validator/Cargo.toml", "r", encoding="utf-8") as f:
        cargo = f.read()
    assert "cdylib" in cargo, "Cargo.toml does not configure a cdylib"


def test_rust_library_directly_on_unpredictable_inputs():
    """Load the submitted ELF library and exercise its exported C ABI symbol."""
    lib = ctypes.CDLL(LIB_PATH)
    assert hasattr(lib, "compute_signature"), "Rust library does not export compute_signature"
    function = lib.compute_signature
    function.argtypes = [ctypes.c_uint64, ctypes.c_uint64]
    function.restype = ctypes.c_uint64

    cases = [
        (0, 0),
        (MASK, MASK),
        (MASK, 0),
        (0, MASK),
        (1 << 63, (1 << 63) - 1),
    ]
    cases.extend((secrets.randbits(64), secrets.randbits(64)) for _ in range(64))
    for token_id, salt in cases:
        assert function(token_id, salt) == legacy_signature(token_id, salt)


def test_functional_py3_wrapper():
    """Verify that the compute_signature function works correctly."""
    assert os.path.isfile(WRAPPER_PATH), f"Wrapper file missing: {WRAPPER_PATH}"
    py3_wrapper = load_wrapper()
    assert hasattr(py3_wrapper, "compute_signature"), "compute_signature function is missing in py3_wrapper.py"
    compute_signature = py3_wrapper.compute_signature

    token_id = 123456789
    salt = 987654321
    expected = ((token_id ^ salt) * 11400714819323198485) % (2**64)
    result = compute_signature(token_id, salt)
    assert result == expected, f"Expected {expected}, got {result} for token_id={token_id}, salt={salt}"

    token_id = 0xFFFFFFFFFFFFFFFF
    salt = 0xFFFFFFFFFFFFFFFF
    expected = 0
    result = compute_signature(token_id, salt)
    assert result == expected, f"Expected {expected}, got {result} for token_id={token_id}, salt={salt}"

    for _ in range(64):
        token_id = secrets.randbits(64)
        salt = secrets.randbits(64)
        assert compute_signature(token_id, salt) == legacy_signature(token_id, salt)


def test_wrapper_declares_ctypes_uint64_interface():
    with open(WRAPPER_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source)
    assert any(isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "CDLL" for node in ast.walk(tree)), "Wrapper does not load a library with ctypes.CDLL"
    assert LIB_PATH in source, "Wrapper does not load the required release library path"
    assert "argtypes" in source and "restype" in source, "Wrapper does not configure argtypes and restype"
    assert source.count("c_uint64") >= 2, "Wrapper does not configure the uint64 ctypes interface"


def test_wrapper_actually_delegates_to_shared_library():
    """Temporarily substitute a secret ABI-compatible library and require its results."""
    multiplier = secrets.randbits(64) | 1
    offset = secrets.randbits(64)
    inputs = [(secrets.randbits(64), secrets.randbits(64)) for _ in range(12)]

    with tempfile.TemporaryDirectory() as temp_dir:
        source_path = os.path.join(temp_dir, "probe.c")
        probe_path = os.path.join(temp_dir, "probe.so")
        with open(source_path, "w", encoding="utf-8") as f:
            f.write(
                "#include <stdint.h>\n"
                "__attribute__((visibility(\"default\"))) "
                "uint64_t compute_signature(uint64_t token_id, uint64_t salt) { "
                f"return (token_id * UINT64_C({multiplier})) ^ (salt + UINT64_C({offset})); }}\n"
            )
        subprocess.run(
            ["gcc", "-shared", "-fPIC", "-O2", source_path, "-o", probe_path],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        backup_path = LIB_PATH + ".verifier-backup"
        assert not os.path.exists(backup_path), f"Unexpected verifier backup path exists: {backup_path}"
        os.replace(LIB_PATH, backup_path)
        try:
            shutil.copyfile(probe_path, LIB_PATH)
            script = r'''
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("isolated_wrapper", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
inputs = json.loads(sys.argv[2])
print(json.dumps([module.compute_signature(a, b) for a, b in inputs]))
'''
            completed = subprocess.run(
                [sys.executable, "-c", script, WRAPPER_PATH, json.dumps(inputs)],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            results = json.loads(completed.stdout.strip())
        finally:
            if os.path.exists(LIB_PATH):
                os.unlink(LIB_PATH)
            os.replace(backup_path, LIB_PATH)

    expected = [(((a * multiplier) & MASK) ^ ((b + offset) & MASK)) for a, b in inputs]
    assert results == expected, "Python wrapper does not delegate calls to the required shared library"


def test_submitted_property_test_is_real_and_passes():
    test_path = "/home/user/test_validator.py"
    with open(test_path, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source)
    functions = [node for node in ast.walk(tree) if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == "test_signature_equivalence"]
    assert functions, "test_signature_equivalence is missing"
    function = functions[0]
    assert any("given" in ast.unparse(decorator) for decorator in function.decorator_list), "test_signature_equivalence is not property-based with Hypothesis"
    assert len([node for node in ast.walk(function) if isinstance(node, ast.Assert)]) >= 1, "Property test contains no assertion"
    normalized = source.replace(" ", "")
    assert "hypothesis" in source and "integers" in source, "Property test does not use Hypothesis integer strategies"
    assert "2**64-1" in normalized or "2**64)-1" in normalized, "Property test does not cover the full uint64 range"

    completed = subprocess.run(
        [sys.executable, "-m", "pytest", test_path, "-x", "--tb=short"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=120,
    )
    assert completed.returncode == 0, "Submitted pytest suite failed when executed:\n" + completed.stdout
    assert "passed" in completed.stdout, "Submitted pytest suite did not execute a passing test"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
