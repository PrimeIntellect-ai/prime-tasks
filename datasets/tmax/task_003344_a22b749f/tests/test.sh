#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

import pytest

EXECUTABLE_PATH = Path("/home/user/rust_linter/target/release/rust_linter")
PROJECT_PATH = Path("/home/user/rust_linter")
EVAL_CLEAN_DIR = Path("/home/user/corpora/eval_clean")
EVAL_EVIL_DIR = Path("/home/user/corpora/eval_evil")
REFERENCE_PATH = Path("/app/legacy_validator")


def run_linter(executable, manifest):
    return subprocess.run(
        [str(executable), str(manifest)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    ).returncode


def test_executable_exists():
    assert EXECUTABLE_PATH.is_file(), f"Executable not found at {EXECUTABLE_PATH}. Did you run 'cargo build --release'?"
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"File at {EXECUTABLE_PATH} is not executable."
    if REFERENCE_PATH.is_file():
        assert EXECUTABLE_PATH.read_bytes() != REFERENCE_PATH.read_bytes(), "Submission is byte-identical to the reference validator."


def test_adversarial_corpus():
    assert EVAL_CLEAN_DIR.is_dir(), f"Clean eval corpus missing: {EVAL_CLEAN_DIR}"
    assert EVAL_EVIL_DIR.is_dir(), f"Evil eval corpus missing: {EVAL_EVIL_DIR}"

    clean_files = [p for p in EVAL_CLEAN_DIR.iterdir() if p.is_file()]
    evil_files = [p for p in EVAL_EVIL_DIR.iterdir() if p.is_file()]

    assert clean_files, "No files found in clean eval corpus."
    assert evil_files, "No files found in evil eval corpus."

    failed_clean = [p.name for p in clean_files if run_linter(EXECUTABLE_PATH, p) != 0]
    failed_evil = [p.name for p in evil_files if run_linter(EXECUTABLE_PATH, p) != 1]

    errors = []
    if failed_clean:
        errors.append(f"{len(failed_clean)} of {len(clean_files)} clean files modified/rejected (expected exit code 0): {', '.join(failed_clean)}")
    if failed_evil:
        errors.append(f"{len(failed_evil)} of {len(evil_files)} evil files bypassed/accepted (expected exit code 1): {', '.join(failed_evil)}")
    if errors:
        pytest.fail(" | ".join(errors))


def fnv_result(script, key):
    value = key
    for byte in script.encode("utf-8"):
        value ^= byte
        value = (value * 1099511628211) & ((1 << 64) - 1)
    return value & 1


def test_makefile_parser_and_c_ffi_on_unpredictable_inputs():
    with tempfile.TemporaryDirectory(prefix="rust_linter_verify_") as temp:
        copied_project = Path(temp) / "rust_linter"
        shutil.copytree(PROJECT_PATH, copied_project, ignore=shutil.ignore_patterns("target", ".git"))

        c_src = copied_project / "c_src"
        assert (c_src / "Makefile").is_file(), "c_src/Makefile is missing."
        assert (c_src / "vm.c").is_file(), "c_src/vm.c is missing."

        key = secrets.randbits(64)
        (c_src / "vm.c").write_text(
            "#include <stdint.h>\n"
            "#include <stddef.h>\n"
            "int evaluate_bytecode(const uint8_t *script, size_t len) {\n"
            f"    uint64_t h = 0x{key:016x}ULL;\n"
            "    for (size_t i = 0; i < len; ++i) {\n"
            "        h ^= (uint64_t)script[i];\n"
            "        h *= 1099511628211ULL;\n"
            "    }\n"
            "    return (int)(h & 1ULL);\n"
            "}\n",
            encoding="utf-8",
        )
        for artifact in (c_src / "vm.o", c_src / "libvm.a"):
            artifact.unlink(missing_ok=True)

        make_result = subprocess.run(
            ["make"], cwd=c_src, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=60
        )
        assert make_result.returncode == 0, f"The repaired Makefile failed to build libvm.a:\n{make_result.stdout}"
        archive = c_src / "libvm.a"
        assert archive.is_file(), "Makefile did not produce c_src/libvm.a."
        ar_result = subprocess.run(["ar", "t", str(archive)], capture_output=True, text=True, timeout=10)
        assert ar_result.returncode == 0 and "vm.o" in ar_result.stdout.split(), "libvm.a is not a valid static archive containing vm.o."

        build_result = subprocess.run(
            ["cargo", "build", "--release"], cwd=copied_project,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=180
        )
        assert build_result.returncode == 0, f"Project failed to build against a fresh C VM:\n{build_result.stdout}"

        instrumented_executable = copied_project / "target/release/rust_linter"
        assert instrumented_executable.is_file() and os.access(instrumented_executable, os.X_OK)
        nm_result = subprocess.run(["nm", "-g", str(instrumented_executable)], capture_output=True, text=True, timeout=15)
        assert nm_result.returncode == 0 and "evaluate_bytecode" in nm_result.stdout, "Final executable is not linked to the C evaluate_bytecode implementation."

        cases = []
        seen = set()
        while len(cases) < 16 or seen != {0, 1}:
            script = secrets.token_hex(secrets.randbelow(40) + 8)
            expected = fnv_result(script, key)
            cases.append((script, expected))
            seen.add(expected)

        manifests = Path(temp) / secrets.token_hex(12)
        manifests.mkdir()
        for index, (script, expected) in enumerate(cases):
            path = manifests / f"{secrets.token_hex(12)}.json"
            payload = {
                "unrelated": secrets.token_hex(9),
                "script": script,
                "sequence": index,
                "nested": {"value": secrets.randbelow(1000000)},
            }
            path.write_text(json.dumps(payload, indent=(index % 4) + 1), encoding="utf-8")
            actual = run_linter(instrumented_executable, path)
            assert actual == expected, (
                f"Instrumented FFI evaluation returned {actual} instead of {expected}; "
                "the executable must deserialize the manifest and use the linked C VM result."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
