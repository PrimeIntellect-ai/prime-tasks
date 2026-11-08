#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import tempfile

HOME = "/home/user"
SOURCE = os.path.join(HOME, "bootstrap_mse.c")
BINARY = os.path.join(HOME, "bootstrap_mse")
REPORT = os.path.join(HOME, "report.txt")
RUN_A = os.path.join(HOME, "run_A.csv")
RUN_B = os.path.join(HOME, "run_B.csv")


def compute_expected_mse(filename, seed):
    with open(filename, "r") as f:
        lines = f.read().strip().split("\n")

    true_vals = []
    pred_vals = []
    for line in lines:
        if line.strip():
            t, p = map(float, line.split(","))
            true_vals.append(t)
            pred_vals.append(p)

    assert len(true_vals) == 10000
    state = seed

    def lcg_rand():
        nonlocal state
        state = (state * 1103515245 + 12345) % 2147483648
        return state

    total_mse = 0.0
    for _ in range(1000):
        iter_sse = 0.0
        for _ in range(10000):
            idx = lcg_rand() % 10000
            diff = true_vals[idx] - pred_vals[idx]
            iter_sse += diff * diff
        total_mse += iter_sse / 10000.0

    return total_mse / 1000.0


def expected_report(path_a, path_b):
    return [
        f"Run A Bootstrap MSE: {compute_expected_mse(path_a, 42):.6f}",
        f"Run B Bootstrap MSE: {compute_expected_mse(path_b, 42):.6f}",
    ]


def assert_report(expected_lines):
    assert os.path.isfile(REPORT), f"Missing required report file: {REPORT}"
    with open(REPORT, "r") as f:
        actual_lines = [line.strip() for line in f.read().strip().split("\n") if line.strip()]
    assert len(actual_lines) == 2, f"Expected exactly 2 lines in {REPORT}, found {len(actual_lines)}"
    assert actual_lines[0] == expected_lines[0], f"Line 1 mismatch. Expected: '{expected_lines[0]}', Found: '{actual_lines[0]}'"
    assert actual_lines[1] == expected_lines[1], f"Line 2 mismatch. Expected: '{expected_lines[1]}', Found: '{actual_lines[1]}'"


def run_program(program, csv_path, seed):
    proc = subprocess.run(
        [program, csv_path, str(seed)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=90,
    )
    assert proc.returncode == 0, f"{program} failed: {proc.stderr}"
    assert re.fullmatch(r"[0-9]+\.[0-9]{6}\n", proc.stdout), \
        f"Output must be one value with exactly 6 decimal places, got {proc.stdout!r}"
    return proc.stdout


def write_synthetic(path, variant):
    with open(path, "w") as f:
        for i in range(10000):
            true_value = (i * (variant + 3)) % 101
            if variant == 1:
                error = ((i * 17 + 5) % 19) - 9
            else:
                error = ((i * 29 + 11) % 31) - 15
            predicted_value = true_value + error
            f.write(f"{true_value}.0,{predicted_value}.0\n")


def candidate_shell_scripts():
    candidates = []
    for name in sorted(os.listdir(HOME)):
        path = os.path.join(HOME, name)
        if not os.path.isfile(path):
            continue
        is_candidate = name.endswith(".sh")
        if not is_candidate:
            try:
                with open(path, "rb") as f:
                    first = f.readline(256)
                is_candidate = first.startswith(b"#!/bin/sh") or first.startswith(b"#!/bin/bash") or first.startswith(b"#!/usr/bin/env bash") or first.startswith(b"#!/usr/bin/env sh")
            except OSError:
                pass
        if is_candidate:
            candidates.append(path)
    return candidates


def test_final_state():
    # Preserve the original report assertions.
    original_expected = expected_report(RUN_A, RUN_B)
    assert_report(original_expected)

    assert os.path.isfile(SOURCE), f"Missing required C source: {SOURCE}"
    assert os.path.isfile(BINARY), f"Missing required compiled binary: {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Compiled binary is not executable: {BINARY}"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF binary"

    with tempfile.TemporaryDirectory() as td:
        synthetic = os.path.join(td, "synthetic.csv")
        write_synthetic(synthetic, 1)

        expected_7 = f"{compute_expected_mse(synthetic, 7):.6f}\n"
        assert run_program(BINARY, synthetic, 7) == expected_7

        rebuilt = os.path.join(td, "bootstrap_mse_rebuilt")
        build = subprocess.run(
            ["gcc", "-O3", SOURCE, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=90,
        )
        assert build.returncode == 0, f"C source did not compile with gcc -O3: {build.stderr}"
        expected_123 = f"{compute_expected_mse(synthetic, 123):.6f}\n"
        assert run_program(rebuilt, synthetic, 123) == expected_123

        assert subprocess.run([rebuilt], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10).returncode != 0, \
            "Program must reject calls without exactly two arguments"
        assert subprocess.run([rebuilt, synthetic, "1", "extra"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10).returncode != 0, \
            "Program must reject calls with more than two arguments"

    scripts = candidate_shell_scripts()
    assert scripts, "Missing required shell script in /home/user"

    saved = {}
    for path in (RUN_A, RUN_B, SOURCE):
        with open(path, "rb") as f:
            saved[path] = (f.read(), stat.S_IMODE(os.stat(path).st_mode))
    old_report = open(REPORT, "rb").read() if os.path.isfile(REPORT) else None
    old_binary = open(BINARY, "rb").read() if os.path.isfile(BINARY) else None
    old_binary_mode = stat.S_IMODE(os.stat(BINARY).st_mode) if os.path.isfile(BINARY) else None

    selected = None
    try:
        for script in scripts:
            for path, (contents, mode) in saved.items():
                with open(path, "wb") as f:
                    f.write(contents)
                os.chmod(path, mode)
            write_synthetic(RUN_A, 1)
            write_synthetic(RUN_B, 2)
            synthetic_expected = expected_report(RUN_A, RUN_B)
            for output in (REPORT, BINARY):
                if os.path.lexists(output):
                    os.remove(output)
            try:
                result = subprocess.run(["bash", script], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=180)
                if result.returncode != 0:
                    continue
                if not os.path.isfile(BINARY) or not os.access(BINARY, os.X_OK):
                    continue
                assert_report(synthetic_expected)
                selected = script
                break
            except (AssertionError, subprocess.SubprocessError, OSError):
                continue
    finally:
        for path, (contents, mode) in saved.items():
            with open(path, "wb") as f:
                f.write(contents)
            os.chmod(path, mode)

    if selected is None:
        if old_report is not None:
            with open(REPORT, "wb") as f:
                f.write(old_report)
        if old_binary is not None:
            with open(BINARY, "wb") as f:
                f.write(old_binary)
            os.chmod(BINARY, old_binary_mode)
        raise AssertionError("No submitted shell script successfully compiled the C program and generated a correct report on derived CSV inputs")

    for output in (REPORT, BINARY):
        if os.path.lexists(output):
            os.remove(output)
    result = subprocess.run(["bash", selected], cwd=HOME, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=180)
    assert result.returncode == 0, f"Report shell script failed on the provided artifacts: {result.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Shell script did not compile /home/user/bootstrap_mse"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Shell script did not produce a compiled ELF binary"
    assert_report(original_expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
