#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile

C_EXECUTABLE = "/home/user/math_ops/math_diff"
C_DIFF = "/home/user/artifacts/c_diff.txt"
RUST_DIFF = "/home/user/artifacts/rust_diff.txt"
PERF_LOG = "/home/user/artifacts/perf.log"
SET_A = "/home/user/data/setA.txt"
SET_B = "/home/user/data/setB.txt"
MANIFEST = "/home/user/verifier/Cargo.toml"
TIME_RE = re.compile(r"real\s+\d+(?:\.\d+)?\nuser\s+\d+(?:\.\d+)?\nsys\s+\d+(?:\.\d+)?\n?\Z")


def run_checked(command, **kwargs):
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120, **kwargs)
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {' '.join(command)}\n"
        f"stdout:\n{result.stdout.decode('utf-8', errors='replace')}\n"
        f"stderr:\n{result.stderr.decode('utf-8', errors='replace')}"
    )
    return result


def expected_output(a_values, b_values):
    values = sorted(set(a_values).symmetric_difference(set(b_values)))
    return "".join(f"{value}\n" for value in values).encode()


def test_datasets_are_original():
    assert os.path.isfile(SET_A), f"Dataset {SET_A} is missing."
    assert os.path.isfile(SET_B), f"Dataset {SET_B} is missing."

    with open(SET_A, "r", encoding="utf-8") as f:
        a_values = [int(line.strip()) for line in f if line.strip()]
    with open(SET_B, "r", encoding="utf-8") as f:
        b_values = [int(line.strip()) for line in f if line.strip()]

    assert a_values == list(range(1, 101, 2)), f"Dataset {SET_A} was altered."
    assert b_values == list(range(1, 101, 3)), f"Dataset {SET_B} was altered."


def test_c_executable_exists():
    assert os.path.isfile(C_EXECUTABLE), f"Executable {C_EXECUTABLE} was not created."
    assert os.access(C_EXECUTABLE, os.X_OK), f"File {C_EXECUTABLE} is not executable."
    with open(C_EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{C_EXECUTABLE} is not a compiled ELF executable."


def test_perf_log():
    assert os.path.isfile(PERF_LOG), f"Performance log {PERF_LOG} was not created."
    with open(PERF_LOG, "r", encoding="utf-8") as f:
        content = f.read()

    assert "real" in content, f"'real' not found in {PERF_LOG}."
    assert "user" in content, f"'user' not found in {PERF_LOG}."
    assert "sys" in content, f"'sys' not found in {PERF_LOG}."
    assert TIME_RE.fullmatch(content), f"{PERF_LOG} is not complete /usr/bin/time -p output."

    timed = run_checked(["/usr/bin/time", "-p", C_EXECUTABLE, SET_A, SET_B])
    timed_stderr = timed.stderr.decode("utf-8", errors="strict")
    assert TIME_RE.fullmatch(timed_stderr), "Fresh /usr/bin/time -p output had an unexpected format."
    with open(C_DIFF, "rb") as f:
        assert timed.stdout == f.read(), "A timed execution of math_diff did not reproduce c_diff.txt."


def test_rust_compiles():
    result = subprocess.run(
        ["cargo", "build", "--manifest-path", MANIFEST],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, f"Rust verifier failed to compile:\n{result.stderr.decode('utf-8')}"


def test_diff_contents_and_execution_provenance():
    assert os.path.isfile(C_DIFF), f"C diff output {C_DIFF} was not created."
    assert os.path.isfile(RUST_DIFF), f"Rust diff output {RUST_DIFF} was not created."

    with open(C_DIFF, "r", encoding="utf-8") as f:
        c_lines = f.read().strip().splitlines()
    with open(RUST_DIFF, "r", encoding="utf-8") as f:
        rust_lines = f.read().strip().splitlines()

    assert c_lines == rust_lines, "C diff and Rust diff outputs do not match."

    assert os.path.isfile(SET_A), f"Dataset {SET_A} is missing."
    assert os.path.isfile(SET_B), f"Dataset {SET_B} is missing."
    with open(SET_A, "r", encoding="utf-8") as f:
        a_vals = set(int(x.strip()) for x in f if x.strip())
    with open(SET_B, "r", encoding="utf-8") as f:
        b_vals = set(int(x.strip()) for x in f if x.strip())

    expected_diff = sorted(a_vals.symmetric_difference(b_vals))
    expected_lines = [str(x) for x in expected_diff]
    assert c_lines == expected_lines, "The output diff does not match the expected symmetric difference."

    with open(C_DIFF, "rb") as f:
        saved_c = f.read()
    with open(RUST_DIFF, "rb") as f:
        saved_rust = f.read()

    fresh_c = run_checked([C_EXECUTABLE, SET_A, SET_B]).stdout
    fresh_rust = run_checked([
        "cargo", "run", "--quiet", "--manifest-path", MANIFEST, "--", SET_A, SET_B
    ]).stdout
    assert fresh_c == saved_c, "Executing math_diff did not reproduce c_diff.txt."
    assert fresh_rust == saved_rust, "Executing the Rust verifier did not reproduce rust_diff.txt."

    with tempfile.TemporaryDirectory() as temp_dir:
        hidden_a = os.path.join(temp_dir, "a.txt")
        hidden_b = os.path.join(temp_dir, "b.txt")
        hidden_a_values = [42, -5, 10, 2, 99]
        hidden_b_values = [3, 42, -5, 100, 8]
        with open(hidden_a, "w", encoding="utf-8") as f:
            f.write("".join(f"{value}\n" for value in hidden_a_values))
        with open(hidden_b, "w", encoding="utf-8") as f:
            f.write("".join(f"{value}\n" for value in hidden_b_values))

        expected = expected_output(hidden_a_values, hidden_b_values)
        hidden_c = run_checked([C_EXECUTABLE, hidden_a, hidden_b]).stdout
        hidden_rust = run_checked([
            "cargo", "run", "--quiet", "--manifest-path", MANIFEST, "--", hidden_a, hidden_b
        ]).stdout
        assert hidden_c == expected, "math_diff failed on verifier-supplied inputs."
        assert hidden_rust == expected, "The Rust verifier failed on verifier-supplied inputs."
        assert hidden_c == hidden_rust, "C and Rust executions disagree on verifier-supplied inputs."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
