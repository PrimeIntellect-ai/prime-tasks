#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import subprocess
import tempfile
import pytest

PROJECT = "/home/user/project"
INTERPRETER = "/home/user/interpreter.sh"
RUN_TESTS = "/home/user/run_tests.sh"
LOG_FILE = "/home/user/test_results.log"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=120, **kwargs)


def test_scripts_exist_and_executable():
    interpreter = "/home/user/interpreter.sh"
    run_tests = "/home/user/run_tests.sh"

    assert os.path.isfile(interpreter), f"{interpreter} does not exist."
    assert os.path.isfile(run_tests), f"{run_tests} does not exist."

    assert os.stat(interpreter).st_mode & stat.S_IXUSR, f"{interpreter} is not executable."
    assert os.stat(run_tests).st_mode & stat.S_IXUSR, f"{run_tests} is not executable."


def test_run_tests_and_verify_output():
    log_file = "/home/user/test_results.log"

    # Remove log file if it exists to ensure a fresh run
    if os.path.exists(log_file):
        os.remove(log_file)

    # Run the test harness script
    result = subprocess.run(
        ["/home/user/run_tests.sh"],
        cwd="/home/user",
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"run_tests.sh failed with return code {result.returncode}.\nstdout: {result.stdout}\nstderr: {result.stderr}"

    assert os.path.isfile(log_file), f"Log file {log_file} was not created by run_tests.sh."

    with open(log_file, "r") as f:
        content = f.read().strip().splitlines()

    expected = ["15", "25", "35", "45", "55"]
    assert content == expected, f"Expected log contents {expected}, but got {content}."


def test_makefile_builds_real_linked_artifacts_and_generator_works():
    cleaned = run(["make", "clean"], cwd=PROJECT)
    assert cleaned.returncode == 0, f"make clean failed:\n{cleaned.stdout}\n{cleaned.stderr}"

    built = run(["make"], cwd=PROJECT)
    assert built.returncode == 0, f"make failed:\n{built.stdout}\n{built.stderr}"

    library = os.path.join(PROJECT, "libasmgen.so")
    generator = os.path.join(PROJECT, "generator")
    assert os.path.isfile(library), "make did not create libasmgen.so"
    assert os.path.isfile(generator), "make did not create generator"
    assert os.access(generator, os.X_OK), "generator is not executable"

    lib_header = run(["readelf", "-h", library])
    assert lib_header.returncode == 0, f"libasmgen.so is not an ELF file: {lib_header.stderr}"
    assert re.search(r"Type:\s+DYN", lib_header.stdout), "libasmgen.so is not a shared object"

    symbols = run(["readelf", "-Ws", library])
    assert symbols.returncode == 0 and re.search(r"\bgenerate_asm\b", symbols.stdout), \
        "libasmgen.so does not export generate_asm"

    gen_header = run(["readelf", "-h", generator])
    assert gen_header.returncode == 0, f"generator is not an ELF executable: {gen_header.stderr}"
    dynamic = run(["readelf", "-d", generator])
    assert dynamic.returncode == 0, f"cannot inspect generator linkage: {dynamic.stderr}"
    assert re.search(r"Shared library: \[libasmgen\.so\]", dynamic.stdout), \
        "generator is not dynamically linked to libasmgen.so"

    for i in range(1, 6):
        path = os.path.join(PROJECT, f"output_{i}.asm")
        if os.path.exists(path):
            os.remove(path)

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = PROJECT + (":" + env["LD_LIBRARY_PATH"] if env.get("LD_LIBRARY_PATH") else "")
    generated = run(["./generator"], cwd=PROJECT, env=env)
    assert generated.returncode == 0, f"generator failed:\n{generated.stdout}\n{generated.stderr}"

    for i in range(1, 6):
        path = os.path.join(PROJECT, f"output_{i}.asm")
        assert os.path.isfile(path), f"generator did not create output_{i}.asm"
        with open(path) as f:
            lines = f.read().splitlines()
        expected = [f"PUSH {i}", "PUSH 10", "MUL", "PUSH 5", "ADD", "PRINT"]
        assert lines == expected, f"Unexpected contents in output_{i}.asm: {lines}"


def test_interpreter_independently_handles_all_commands():
    rng = random.SystemRandom()
    program = []
    expected = []

    for _ in range(8):
        a, b = rng.randint(-1000, 1000), rng.randint(-1000, 1000)
        c = rng.choice([n for n in range(-12, 13) if n != 0])
        d = rng.randint(-1000, 1000)
        program.extend([
            f"PUSH {a}", f"PUSH {b}", "ADD", f"PUSH {c}", "MUL",
            f"PUSH {d}", "SUB", "PRINT"
        ])
        expected.append(str((a + b) * c - d))

        e, f, g = rng.randint(-1000, 1000), rng.randint(-1000, 1000), rng.randint(-1000, 1000)
        program.extend([f"PUSH {e}", f"PUSH {f}", "SUB", f"PUSH {g}", "ADD", "PRINT"])
        expected.append(str(e - f + g))

    fd, asm_path = tempfile.mkstemp(prefix="interpreter_check_", suffix=".asm")
    try:
        with os.fdopen(fd, "w") as asm:
            asm.write("\n".join(program) + "\n")
        result = run([INTERPRETER, asm_path], cwd="/home/user")
    finally:
        os.remove(asm_path)

    assert result.returncode == 0, f"interpreter failed:\n{result.stdout}\n{result.stderr}"
    assert result.stdout.strip().splitlines() == expected, \
        f"interpreter returned incorrect results: expected {expected}, got {result.stdout!r}"


def test_harness_rebuilds_runs_generator_and_interprets_outputs():
    source_path = os.path.join(PROJECT, "asmgen.c")
    with open(source_path, "rb") as f:
        original_source = f.read()

    alternate_source = r'''#include <stdio.h>
#include "asmgen.h"
void generate_asm(int id, const char* filename) {
    FILE *f = fopen(filename, "w");
    if (!f) return;
    fprintf(f, "PUSH %d\n", id);
    fprintf(f, "PUSH 7\n");
    fprintf(f, "ADD\n");
    fprintf(f, "PUSH 2\n");
    fprintf(f, "MUL\n");
    fprintf(f, "PUSH 3\n");
    fprintf(f, "SUB\n");
    fprintf(f, "PRINT\n");
    fclose(f);
}
'''

    result = None
    content = None
    try:
        with open(source_path, "w") as f:
            f.write(alternate_source)
        if os.path.exists(LOG_FILE):
            os.remove(LOG_FILE)
        result = run([RUN_TESTS], cwd="/home/user")
        if os.path.isfile(LOG_FILE):
            with open(LOG_FILE) as f:
                content = f.read().strip().splitlines()
    finally:
        with open(source_path, "wb") as f:
            f.write(original_source)
        subprocess.run(["make", "clean"], cwd=PROJECT, capture_output=True, text=True)
        subprocess.run(["make"], cwd=PROJECT, capture_output=True, text=True)

    assert result is not None and result.returncode == 0, \
        f"run_tests.sh failed with changed generator input:\n{getattr(result, 'stdout', '')}\n{getattr(result, 'stderr', '')}"
    expected = ["13", "15", "17", "19", "21"]
    assert content == expected, \
        f"run_tests.sh did not rebuild, run, and interpret the generated files; expected {expected}, got {content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
