#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import math
import re
import secrets
import subprocess
import tempfile
from pathlib import Path


def get_expected_t(p):
    t = 1.0
    for _ in range(100):
        f = 1.0 - math.exp(-0.5 * t) + 0.1 * t - p
        if abs(f) < 1e-6:
            break
        df = 0.5 * math.exp(-0.5 * t) + 0.1
        t = t - f / df
    return t


def test_divergence_times_csv():
    csv_path = "/home/user/divergence_times.csv"
    assert os.path.exists(csv_path), f"Missing file: {csv_path}"

    expected_p_values = [0.10, 0.25, 0.50, 0.75]

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_p_values), f"Expected {len(expected_p_values)} lines in {csv_path}, found {len(lines)}"

    for i, line in enumerate(lines):
        parts = line.split(',')
        assert len(parts) == 2, f"Invalid format in CSV line: {line}"

        p_val = float(parts[0])
        t_val = float(parts[1])

        expected_p = expected_p_values[i]
        expected_t = get_expected_t(expected_p)

        assert math.isclose(p_val, expected_p, abs_tol=1e-4), f"Expected p={expected_p}, got {p_val}"
        assert math.isclose(t_val, expected_t, abs_tol=1e-4), f"Expected t={expected_t:.4f} for p={p_val}, got {t_val}"


def test_plot_sh_exists():
    script_path = "/home/user/plot.sh"
    assert os.path.exists(script_path), f"Missing script: {script_path}"
    assert os.path.isfile(script_path), f"Not a file: {script_path}"


def test_plot_txt():
    plot_path = "/home/user/plot.txt"
    assert os.path.exists(plot_path), f"Missing file: {plot_path}"

    expected_p_values = [0.10, 0.25, 0.50, 0.75]

    with open(plot_path, "r") as f:
        lines = [line.strip("\n") for line in f if line.strip("\n")]

    assert len(lines) == len(expected_p_values), f"Expected {len(expected_p_values)} lines in {plot_path}, found {len(lines)}"

    for i, line in enumerate(lines):
        expected_p = expected_p_values[i]
        expected_t = get_expected_t(expected_p)
        num_asterisks = int(math.floor(expected_t * 10))

        expected_p_str = f"{expected_p:.2f}"
        csv_path = "/home/user/divergence_times.csv"
        if os.path.exists(csv_path):
            with open(csv_path, "r") as csv_f:
                csv_lines = [l.strip() for l in csv_f if l.strip()]
                if i < len(csv_lines):
                    expected_p_str = csv_lines[i].split(',')[0]

        expected_line = f"{expected_p_str} | " + ("*" * num_asterisks)
        assert line == expected_line, f"Line {i+1} in {plot_path} is incorrect. Expected: '{expected_line}', Got: '{line}'"


def test_solver_source_compiles_and_handles_unseen_inputs():
    source = Path("/home/user/divergence_solver.cpp")
    assert source.exists(), f"Missing file: {source}"
    assert source.is_file(), f"Not a file: {source}"

    with tempfile.TemporaryDirectory() as td:
        td_path = Path(td)
        binary = td_path / "divergence_solver"
        build = subprocess.run(
            ["g++", "-std=c++17", "-O2", str(source), "-o", str(binary)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, f"divergence_solver.cpp did not compile:\n{build.stderr}"
        assert binary.is_file(), "Compilation did not produce an executable"

        values = []
        while len(values) < 9:
            p = (20000 + secrets.randbelow(1280001)) / 1000000.0
            if p not in values:
                values.append(p)

        (td_path / "sequence_data.txt").write_text(
            "".join(f"{p:.6f}\n" for p in values), encoding="utf-8"
        )
        run = subprocess.run(
            [str(binary)],
            cwd=td,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert run.returncode == 0, f"Compiled solver failed on unseen input:\n{run.stderr}"

        output = td_path / "divergence_times.csv"
        assert output.is_file(), "Compiled solver did not create divergence_times.csv"
        lines = [line.strip() for line in output.read_text(encoding="utf-8").splitlines() if line.strip()]
        assert len(lines) == len(values), f"Expected {len(values)} solver results, found {len(lines)}"

        for p, line in zip(values, lines):
            parts = line.split(',')
            assert len(parts) == 2, f"Invalid solver CSV line: {line}"
            assert re.fullmatch(r"[-+]?\d+\.\d{4}", parts[1]), f"t is not rounded to exactly 4 decimal places: {parts[1]}"
            try:
                actual_p = float(parts[0])
                actual_t = float(parts[1])
            except ValueError:
                raise AssertionError(f"Non-numeric solver CSV line: {line}")
            expected_t = get_expected_t(p)
            assert math.isclose(actual_p, p, rel_tol=0.0, abs_tol=5.1e-5), f"Solver changed input p={p}: {parts[0]}"
            assert math.isclose(actual_t, expected_t, rel_tol=0.0, abs_tol=5.1e-5), (
                f"Incorrect result for unseen p={p}: expected {expected_t:.4f}, got {parts[1]}"
            )


def test_plot_script_executes_on_unseen_csv():
    csv_path = Path("/home/user/divergence_times.csv")
    script_path = Path("/home/user/plot.sh")
    original = csv_path.read_bytes() if csv_path.exists() else None

    rows = []
    expected = []
    for _ in range(7):
        p_token = f"0.{secrets.randbelow(1000000):06d}"
        stars = secrets.randbelow(36)
        t_token = f"{(stars + 0.37) / 10:.4f}"
        rows.append(f"{p_token},{t_token}")
        expected.append(f"{p_token} | " + "*" * stars)

    try:
        csv_path.write_text("\n".join(rows) + "\n", encoding="utf-8")
        run = subprocess.run(
            ["bash", str(script_path)],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert run.returncode == 0, f"plot.sh failed when executed:\n{run.stderr}"
        actual = run.stdout.splitlines()
        assert actual == expected, f"plot.sh output is incorrect. Expected {expected!r}, got {actual!r}"
    finally:
        if original is None:
            csv_path.unlink(missing_ok=True)
        else:
            csv_path.write_bytes(original)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
