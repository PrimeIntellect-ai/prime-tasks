#!/bin/bash
set -e
mkdir -p /logs/verifier

# Force the orchestration script to recreate all requested build products.
rm -f /home/user/project/build/libmath_ops.so \
      /home/user/project/build/librust_compute.so \
      /home/user/project/build/exit42 \
      /home/user/project/output/results_sorted.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import json
import os
import random
import subprocess

PROJECT = "/home/user/project"
BUILD = os.path.join(PROJECT, "build")


def test_orchestration_workflow_runs():
    script_path = os.path.join(PROJECT, "build_and_run.sh")
    assert os.path.isfile(script_path), f"Missing orchestration script: {script_path}"

    result = subprocess.run(
        ["bash", script_path],
        cwd=PROJECT,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"Orchestration script failed with code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_shared_libraries_exist():
    math_so = "/home/user/project/build/libmath_ops.so"
    rust_so = "/home/user/project/build/librust_compute.so"

    assert os.path.isfile(math_so), f"Missing shared library: {math_so}"
    assert os.path.isfile(rust_so), f"Missing shared library: {rust_so}"


def test_shared_libraries_are_loadable_and_compute_works():
    math_so = os.path.join(BUILD, "libmath_ops.so")
    rust_so = os.path.join(BUILD, "librust_compute.so")

    for path in (math_so, rust_so):
        header = subprocess.run(
            ["readelf", "-h", path], capture_output=True, text=True
        )
        assert header.returncode == 0, f"Not a valid ELF library: {path}\n{header.stderr}"
        assert "DYN (Shared object file)" in header.stdout, f"Not a shared object: {path}"

    dynamic = subprocess.run(
        ["readelf", "-d", rust_so], capture_output=True, text=True, check=True
    ).stdout
    assert "Shared library: [libmath_ops.so]" in dynamic, (
        "librust_compute.so does not dynamically link to libmath_ops.so"
    )

    rng = random.Random(731942)
    cases = []
    for length in (1, 2, 5, 17, 64):
        values = [rng.randint(-10000, 10000) for _ in range(length)]
        cases.append(values)

    helper = r'''
import ctypes, json, os, sys
build, encoded = sys.argv[1], sys.argv[2]
cases = json.loads(encoded)
math = ctypes.CDLL(os.path.join(build, "libmath_ops.so"), mode=ctypes.RTLD_GLOBAL)
math.add.argtypes = [ctypes.c_int, ctypes.c_int]
math.add.restype = ctypes.c_int
assert math.add(123, -45) == 78
lib = ctypes.CDLL(os.path.join(build, "librust_compute.so"))
lib.compute.argtypes = [ctypes.POINTER(ctypes.c_int), ctypes.c_size_t]
lib.compute.restype = ctypes.c_int
answers = []
for values in cases:
    arr = (ctypes.c_int * len(values))(*values)
    answers.append(lib.compute(arr, len(values)))
print(json.dumps(answers))
'''
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = BUILD + os.pathsep + env.get("LD_LIBRARY_PATH", "")
    result = subprocess.run(
        ["python3", "-c", helper, BUILD, json.dumps(cases)],
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Libraries could not be loaded or compute failed.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert json.loads(result.stdout.strip()) == [sum(values) for values in cases]


def test_fixed_python_script_runs():
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = BUILD + os.pathsep + env.get("LD_LIBRARY_PATH", "")
    result = subprocess.run(
        ["python3", os.path.join(PROJECT, "scripts", "run.py")],
        cwd=PROJECT,
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"run.py failed:\n{result.stderr}"
    assert result.stdout.strip().splitlines() == [
        "TestA: 6",
        "TestC: 60",
        "TestB: 10",
    ]


def test_exit42_executable():
    exe_path = "/home/user/project/build/exit42"
    assert os.path.isfile(exe_path), f"Missing executable: {exe_path}"
    assert os.access(exe_path, os.X_OK), f"File is not executable: {exe_path}"

    header = subprocess.run(["readelf", "-h", exe_path], capture_output=True, text=True)
    assert header.returncode == 0, f"exit42 is not a valid ELF executable:\n{header.stderr}"
    assert "Machine:" in header.stdout and "X86-64" in header.stdout

    program_headers = subprocess.run(
        ["readelf", "-l", exe_path], capture_output=True, text=True, check=True
    ).stdout
    dynamic = subprocess.run(
        ["readelf", "-d", exe_path], capture_output=True, text=True
    )
    assert "INTERP" not in program_headers, "exit42 is not a static executable"
    assert dynamic.returncode != 0 or "There is no dynamic section" in dynamic.stdout, (
        "exit42 unexpectedly has a dynamic section"
    )

    result = subprocess.run([exe_path], capture_output=True)
    assert result.returncode == 42, f"Expected exit code 42, got {result.returncode}"


def test_assembly_source_builds_to_exit42():
    source = os.path.join(PROJECT, "src", "exit42.s")
    assert os.path.isfile(source), f"Missing assembly source: {source}"
    subprocess.run(["as", source, "-o", "/tmp/exit42_test.o"], check=True, capture_output=True)
    subprocess.run(
        ["ld", "-static", "/tmp/exit42_test.o", "-o", "/tmp/exit42_test"],
        check=True,
        capture_output=True,
    )
    result = subprocess.run(["/tmp/exit42_test"], capture_output=True)
    assert result.returncode == 42, (
        f"Assembly source produced exit code {result.returncode}, expected 42"
    )


def test_results_sorted():
    results_path = "/home/user/project/output/results_sorted.txt"
    assert os.path.isfile(results_path), f"Missing results file: {results_path}"

    with open(results_path, "r") as f:
        content = f.read().strip()

    expected = "TestA: 6\nTestB: 10\nTestC: 60"
    assert content == expected, f"Output mismatch in {results_path}.\nExpected:\n{expected}\nGot:\n{content}"


def test_rust_compiles():
    rust_file = "/home/user/project/src/lib.rs"
    assert os.path.isfile(rust_file), f"Missing Rust source file: {rust_file}"

    result = subprocess.run(
        ["rustc", "--crate-type", "lib", "--emit=metadata", rust_file, "-o", "/tmp/lib_test.rmeta"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, f"Rust compilation failed (borrow checker error still present?):\n{result.stderr}"


def test_build_and_run_script_exists():
    script_path = "/home/user/project/build_and_run.sh"
    assert os.path.isfile(script_path), f"Missing orchestration script: {script_path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
