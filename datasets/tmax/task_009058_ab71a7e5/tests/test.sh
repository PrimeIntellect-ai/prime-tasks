#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import re
import shutil
import subprocess
import tempfile
import pytest


def run_processor(path, n, timeout=15):
    result = subprocess.run([path, str(n)], capture_output=True, text=True, timeout=timeout)
    assert result.returncode == 0, f"Execution of {path} with {n} failed: {result.stderr}"
    return result.stdout.strip()


def assert_elf_executable(path):
    assert os.path.isfile(path), f"Executable {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def test_fuzz_sh_exists_and_executable():
    fuzz_path = "/home/user/fuzz.sh"
    assert os.path.isfile(fuzz_path), f"File {fuzz_path} does not exist."
    assert os.access(fuzz_path, os.X_OK), f"File {fuzz_path} is not executable."

    with open(fuzz_path, 'r') as f:
        content = f.read()

    assert "processor" in content, f"{fuzz_path} does not appear to run the processor executable."
    assert "for" in content or "while" in content, f"{fuzz_path} does not appear to contain a loop."

    processor = "/home/user/processor"
    assert_elf_executable(processor)

    # The initial executable must behave like the inherited (possibly flaky)
    # processor, rather than being a text file or fixed-output placeholder.
    rng = random.SystemRandom()
    for n in [rng.randint(10000, 50000) for _ in range(4)]:
        output = run_processor(processor, n)
        assert re.fullmatch(r"-?\d+", output), f"Initial processor produced non-integer output: {output!r}"
        value = int(output)
        assert 0 <= value <= n, f"Initial processor produced impossible sum {value} for N={n}."

    # Exercise the fuzzer itself with a controlled processor. First verify that
    # it performs exactly 50 successful in-range trials, then inject a mismatch
    # and verify that it stops immediately with status 1.
    with tempfile.TemporaryDirectory() as td:
        backup = os.path.join(td, "processor.backup")
        shutil.copy2(processor, backup)
        log_path = os.path.join(td, "calls.log")
        mode_path = os.path.join(td, "mode")
        shim = f'''#!/usr/bin/python3
import os, sys
arg = sys.argv[1] if len(sys.argv) > 1 else ""
with open({log_path!r}, "a") as f:
    f.write(arg + "\\n")
try:
    n = int(arg)
except Exception:
    sys.exit(2)
mode = open({mode_path!r}).read().strip() if os.path.exists({mode_path!r}) else "ok"
print(n + 1 if mode == "bad" else n)
'''
        try:
            with open(processor, "w") as f:
                f.write(shim)
            os.chmod(processor, 0o755)

            with open(mode_path, "w") as f:
                f.write("ok")
            result = subprocess.run([fuzz_path], capture_output=True, text=True, timeout=20)
            assert result.returncode == 0, f"Fuzzer failed when all outputs were correct: {result.stdout}{result.stderr}"
            with open(log_path) as f:
                calls = [line.strip() for line in f if line.strip()]
            assert len(calls) == 50, f"Fuzzer made {len(calls)} successful trials, expected 50."
            values = [int(x) for x in calls]
            assert all(10000 <= x <= 50000 for x in values), "Fuzzer used an argument outside 10000..50000."
            assert len(set(values)) > 1, "Fuzzer arguments do not appear to be random."

            open(log_path, "w").close()
            with open(mode_path, "w") as f:
                f.write("bad")
            result = subprocess.run([fuzz_path], capture_output=True, text=True, timeout=10)
            assert result.returncode == 1, "Fuzzer did not exit with code 1 after a mismatch."
            with open(log_path) as f:
                calls = [line.strip() for line in f if line.strip()]
            assert len(calls) == 1, f"Fuzzer did not stop immediately after a mismatch; it made {len(calls)} calls."
            assert 10000 <= int(calls[0]) <= 50000
        finally:
            shutil.copy2(backup, processor)


def test_concurrent_processor_fixed():
    cpp_path = "/home/user/concurrent_processor.cpp"
    assert os.path.isfile(cpp_path), f"File {cpp_path} does not exist."

    with open(cpp_path, 'r') as f:
        content = f.read()

    has_atomic = "std::atomic" in content
    has_mutex = "std::mutex" in content or "pthread_mutex" in content

    assert has_atomic or has_mutex, f"{cpp_path} does not seem to use std::atomic or a mutex to fix the race condition."
    assert "std::thread" in content, "The required multithreading logic was removed."
    assert "process_chunk" in content, "The chunk-processing structure was removed."
    assert ".join(" in content, "Worker threads do not appear to be joined."
    assert re.search(r"\b(for|while)\s*\(", content), "The array-processing loop was removed."

    # Compile the submitted source independently so a fake processor_fixed
    # cannot conceal source that does not build or does not compute correctly.
    built = "/tmp/processor_from_submitted_source"
    compile_result = subprocess.run(
        ["g++", "-pthread", "-O2", cpp_path, "-o", built],
        capture_output=True, text=True, timeout=30
    )
    assert compile_result.returncode == 0, f"Submitted source does not compile with g++ -pthread -O2:\n{compile_result.stderr}"
    assert_elf_executable(built)

    rng = random.SystemRandom()
    test_values = [
        rng.randint(10000, 50000),
        rng.randint(50001, 200000),
        rng.randint(200001, 700000),
        1000003,
    ]
    for n in test_values:
        for _ in range(3):
            output = run_processor(built, n)
            assert output == str(n), f"Source-built processor returned {output!r}, expected {n}."


def test_final_result_txt():
    result_path = "/home/user/final_result.txt"
    assert os.path.isfile(result_path), f"File {result_path} does not exist."

    with open(result_path, 'r') as f:
        content = f.read().strip()

    assert content == "500000", f"{result_path} contains '{content}', expected '500000'."

    output = run_processor("/home/user/processor_fixed", 500000)
    assert output == content, "final_result.txt does not match processor_fixed 500000."


def test_processor_fixed_executable():
    exe_path = "/home/user/processor_fixed"
    assert os.path.isfile(exe_path), f"Executable {exe_path} does not exist."
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."
    assert_elf_executable(exe_path)
    assert_elf_executable("/home/user/processor")

    with open(exe_path, "rb") as f:
        fixed_hash = hashlib.sha256(f.read()).digest()
    with open("/home/user/processor", "rb") as f:
        initial_hash = hashlib.sha256(f.read()).digest()
    assert fixed_hash != initial_hash, "processor and processor_fixed are identical; the initial buggy build was not preserved."

    # Run multiple times to ensure no race condition remains
    for _ in range(20):
        result = subprocess.run([exe_path, "1000000"], capture_output=True, text=True)
        assert result.returncode == 0, f"Execution of {exe_path} failed."
        output = result.stdout.strip()
        assert output == "1000000", f"Expected output 1000000, but got {output}. Race condition might still exist."

    rng = random.SystemRandom()
    for n in [rng.randint(10000, 99999), rng.randint(100000, 999999), 1000003, 1234577]:
        output = run_processor(exe_path, n)
        assert output == str(n), f"Expected output {n}, but got {output}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
