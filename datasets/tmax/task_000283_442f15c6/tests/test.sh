#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import secrets
import subprocess
import tempfile

import pytest

BINARY_PATH = "/app/bin/waf_filter"
RUST_DIR = "/app/src/rust_engine"
GO_DIR = "/app/src/waf_filter"


def run_checked(cmd, **kwargs):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kwargs)


def assert_result(binary, path, clean):
    result = subprocess.run([binary, path], capture_output=True, text=True, timeout=5)
    expected_code = 0 if clean else 1
    expected_text = "CLEAN" if clean else "EVIL"
    assert result.returncode == expected_code, (
        f"{path!r}: expected status {expected_code}, got {result.returncode}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert expected_text in result.stdout, (
        f"{path!r}: expected {expected_text!r} in stdout, got {result.stdout!r}"
    )


def test_waf_filter_executable_exists():
    assert os.path.isfile(BINARY_PATH), f"The Go binary is missing at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"The file at {BINARY_PATH} is not executable"


def test_waf_filter_adversarial_corpus():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isdir(clean_dir), f"Clean corpus directory missing at {clean_dir}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing at {evil_dir}"

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_modified = []
    for cf in clean_files:
        try:
            result = subprocess.run([BINARY_PATH, cf], capture_output=True, text=True, timeout=5)
            if result.returncode != 0 or "CLEAN" not in result.stdout:
                clean_modified.append(os.path.basename(cf))
        except Exception as e:
            clean_modified.append(f"{os.path.basename(cf)} (error: {e})")

    evil_bypassed = []
    for ef in evil_files:
        try:
            result = subprocess.run([BINARY_PATH, ef], capture_output=True, text=True, timeout=5)
            if result.returncode != 1 or "EVIL" not in result.stdout:
                evil_bypassed.append(os.path.basename(ef))
        except Exception as e:
            evil_bypassed.append(f"{os.path.basename(ef)} (error: {e})")

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    assert not errors, "Adversarial corpus validation failed:\n" + "\n".join(errors)


def test_rust_library_and_cgo_source_build():
    assert os.path.isfile(os.path.join(RUST_DIR, "Cargo.toml")), "Rust Cargo.toml is missing"
    assert os.path.isfile(os.path.join(RUST_DIR, "src", "lib.rs")), "Rust src/lib.rs is missing"

    existing_archives = glob.glob(os.path.join(RUST_DIR, "**", "librust_engine.a"), recursive=True)
    assert any(os.path.isfile(p) and os.path.getsize(p) > 0 for p in existing_archives), \
        "Built librust_engine.a is missing"

    run_checked(["cargo", "build"], cwd=RUST_DIR, timeout=120)
    rebuilt_archive = os.path.join(RUST_DIR, "target", "debug", "librust_engine.a")
    assert os.path.isfile(rebuilt_archive) and os.path.getsize(rebuilt_archive) > 0, \
        "Cargo did not produce the Rust static library"
    run_checked(["ar", "t", rebuilt_archive], timeout=20)

    go_mod = os.path.join(GO_DIR, "go.mod")
    main_go = os.path.join(GO_DIR, "main.go")
    assert os.path.isfile(go_mod), "Go module was not initialized"
    assert os.path.isfile(main_go), "Go main.go is missing"

    source = open(main_go, "r", encoding="utf-8").read()
    assert re.search(r'import\s+"C"', source), "main.go does not use cgo"
    assert "C.evaluate_safe" in source, "main.go does not call the Rust evaluate_safe FFI function"
    assert "rust_engine" in source, "main.go does not declare linkage to librust_engine"

    build_dir = tempfile.mkdtemp(prefix="verify-go-build-")
    rebuilt_binary = os.path.join(build_dir, "waf_filter")
    env = os.environ.copy()
    env["CGO_ENABLED"] = "1"
    env["GOCACHE"] = os.path.join(build_dir, "gocache")
    env.pop("GOFLAGS", None)
    run_checked(["go", "build", "-o", rebuilt_binary, "."], cwd=GO_DIR, env=env, timeout=120)
    assert os.path.isfile(rebuilt_binary) and os.access(rebuilt_binary, os.X_OK)

    symbols = run_checked(["go", "tool", "nm", rebuilt_binary], timeout=30).stdout
    assert "evaluate_safe" in symbols, "Rebuilt Go binary has no evaluate_safe/cgo symbol"

    pytest.rebuilt_binary = rebuilt_binary


def make_safe_expression(rng, depth):
    value = str(rng.randint(0, 99999))
    nested = "(" * depth + value + ")" * depth
    op = rng.choice(["+", "-", "*", "/"])
    rhs = str(rng.randint(1, 99999))
    left_space = " " * rng.randint(0, 3)
    right_space = " " * rng.randint(0, 3)
    return f"{left_space}{nested} {op} {rhs}{right_space}"


def test_generated_unpredictable_expressions():
    rebuilt_binary = getattr(pytest, "rebuilt_binary", None)
    assert rebuilt_binary and os.path.isfile(rebuilt_binary), "Fresh Go build was not produced"

    rng = random.Random(secrets.randbits(128))
    cases = []

    for depth in range(0, 8):
        cases.append((make_safe_expression(rng, depth), True))
    for _ in range(24):
        cases.append((make_safe_expression(rng, rng.randint(0, 7)), True))

    for depth in range(8, 15):
        cases.append((make_safe_expression(rng, depth), False))
    for _ in range(20):
        cases.append((make_safe_expression(rng, rng.randint(8, 20)), False))

    forbidden = ["a", ";", "_", ".", "[", "]", ",", "\t", "\n", "é", "#", "="]
    for ch in forbidden:
        base = make_safe_expression(rng, rng.randint(0, 7))
        pos = rng.randint(0, len(base))
        cases.append((base[:pos] + ch + base[pos:], False))

    rng.shuffle(cases)
    with tempfile.TemporaryDirectory(prefix="waf-random-inputs-") as td:
        for index, (expression, clean) in enumerate(cases):
            name = secrets.token_hex(12) + f"-{index}.dat"
            path = os.path.join(td, name)
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write(expression)
            assert_result(BINARY_PATH, path, clean)
            assert_result(rebuilt_binary, path, clean)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
