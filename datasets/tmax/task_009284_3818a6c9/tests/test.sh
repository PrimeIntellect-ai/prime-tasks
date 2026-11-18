#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shlex
import stat
import subprocess
import tempfile

import pytest


def test_files_exist():
    expected_files = [
        "/home/user/compute_cov.c",
        "/home/user/compute_cov",
        "/home/user/test_reproducibility.sh",
        "/home/user/split1.csv",
        "/home/user/split2.csv",
        "/home/user/cov1.txt",
        "/home/user/cov2.txt"
    ]
    for file_path in expected_files:
        assert os.path.isfile(file_path), f"Expected file {file_path} does not exist."


def test_sh_executable():
    sh_path = "/home/user/test_reproducibility.sh"
    assert os.access(sh_path, os.X_OK), f"Script {sh_path} is not executable."


def test_cov_outputs():
    cov1_path = "/home/user/cov1.txt"
    cov2_path = "/home/user/cov2.txt"

    expected_cov1 = [
        "2.4570 2.2380 2.2130",
        "2.2380 2.2230 2.0620",
        "2.2130 2.0620 2.0570"
    ]

    expected_cov2 = [
        "2.5750 2.3600 2.6500",
        "2.3600 2.2670 2.4930",
        "2.6500 2.4930 2.7670"
    ]

    with open(cov1_path, 'r') as f:
        cov1_lines = [line.strip() for line in f if line.strip()]

    assert cov1_lines == expected_cov1, f"Content of {cov1_path} does not match expected output. Got: {cov1_lines}"

    with open(cov2_path, 'r') as f:
        cov2_lines = [line.strip() for line in f if line.strip()]

    assert cov2_lines == expected_cov2, f"Content of {cov2_path} does not match expected output. Got: {cov2_lines}"


def covariance_text(rows):
    n = len(rows)
    means = [sum(row[j] for row in rows) / n for j in range(3)]
    matrix = []
    for i in range(3):
        out_row = []
        for j in range(3):
            value = sum((row[i] - means[i]) * (row[j] - means[j]) for row in rows) / (n - 1)
            out_row.append(value)
        matrix.append(out_row)
    return "\n".join(" ".join(f"{value:.4f}" for value in row) for row in matrix) + "\n", matrix


def make_random_rows():
    rng = random.SystemRandom()
    while True:
        rows = []
        for _ in range(8):
            x = rng.randint(-180, 180) / 10.0
            y = 1.7 * x + rng.randint(-40, 40) / 10.0
            z = -0.8 * x + rng.randint(-50, 50) / 10.0
            rows.append([x, y, z])
        expected, matrix = covariance_text(rows)
        # Keep all values comfortably away from a four-decimal rounding boundary
        # so mathematically equivalent C implementations are treated alike.
        safe = True
        for row in matrix:
            for value in row:
                scaled = abs(value) * 10000.0
                if abs((scaled - int(scaled)) - 0.5) < 0.02:
                    safe = False
        if safe:
            return rows, expected


def exercise_program(executable, rows, expected, directory):
    input_path = os.path.join(directory, "random_input.csv")
    output_path = os.path.join(directory, "random_output.txt")
    with open(input_path, "w", encoding="utf-8") as f:
        for row in rows:
            f.write(",".join(f"{value:.1f}" for value in row) + "\n")

    no_args = subprocess.run([executable], cwd="/home/user", stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, timeout=5)
    assert no_args.returncode != 0, "compute_cov must reject calls without exactly two arguments"
    too_many = subprocess.run([executable, input_path, output_path, "extra"], cwd="/home/user",
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    assert too_many.returncode != 0, "compute_cov must reject calls with more than two arguments"

    result = subprocess.run([executable, input_path, output_path], cwd="/home/user",
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert result.returncode == 0, f"compute_cov failed: {result.stderr.decode(errors='replace')}"
    assert os.path.isfile(output_path), "compute_cov did not create its requested output file"
    with open(output_path, "r", encoding="utf-8") as f:
        actual = f.read()
    assert actual == expected, f"Incorrect covariance output. Expected {expected!r}, got {actual!r}"
    for line in actual.splitlines():
        assert re.fullmatch(r"-?\d+\.\d{4} -?\d+\.\d{4} -?\d+\.\d{4}", line), \
            f"Output row has invalid formatting: {line!r}"


def test_compiled_program_and_source_on_derived_input():
    executable = "/home/user/compute_cov"
    source = "/home/user/compute_cov.c"
    assert os.access(executable, os.X_OK), "compute_cov is not executable"
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "compute_cov is not a compiled executable"

    rows, expected = make_random_rows()
    with tempfile.TemporaryDirectory(prefix="cov_test_") as directory:
        exercise_program(executable, rows, expected, directory)

        rebuilt = os.path.join(directory, "compute_cov_rebuilt")
        compile_result = subprocess.run(
            ["gcc", "-std=c11", "-O2", source, "-lm", "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert compile_result.returncode == 0, \
            f"compute_cov.c does not compile: {compile_result.stderr.decode(errors='replace')}"
        exercise_program(rebuilt, rows, expected, directory)


def test_reproducibility_script_runs_real_program_and_pipeline():
    executable = "/home/user/compute_cov"
    script = "/home/user/test_reproducibility.sh"
    original = f"/tmp/compute_cov.original.{os.getpid()}"
    call_log = f"/tmp/compute_cov.calls.{os.getpid()}"

    for path in ["/home/user/split1.csv", "/home/user/split2.csv",
                 "/home/user/cov1.txt", "/home/user/cov2.txt", call_log]:
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    original_mode = stat.S_IMODE(os.stat(executable).st_mode)
    os.rename(executable, original)
    wrapper = f'''#!/bin/bash
printf '%s\\t%s\\t%s\\t%s\\n' "$#" "$PWD" "${{1-}}" "${{2-}}" >> {shlex.quote(call_log)}
exec {shlex.quote(original)} "$@"
'''
    try:
        with open(executable, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.chmod(executable, 0o755)
        result = subprocess.run([script], cwd="/home/user", stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=20)
        assert result.returncode == 0, \
            f"test_reproducibility.sh failed: {result.stderr.decode(errors='replace')}"
    finally:
        try:
            os.unlink(executable)
        except FileNotFoundError:
            pass
        os.rename(original, executable)
        os.chmod(executable, original_mode)

    assert os.path.isfile(call_log), "The reproducibility script did not invoke /home/user/compute_cov"
    observed = set()
    with open(call_log, "r", encoding="utf-8") as f:
        for line in f:
            fields = line.rstrip("\n").split("\t")
            assert len(fields) == 4 and fields[0] == "2", \
                "The script must invoke compute_cov with exactly an input and output path"
            cwd, input_arg, output_arg = fields[1:]
            input_path = os.path.realpath(os.path.join(cwd, input_arg))
            output_path = os.path.realpath(os.path.join(cwd, output_arg))
            observed.add((input_path, output_path))

    assert ("/home/user/split1.csv", "/home/user/cov1.txt") in observed
    assert ("/home/user/split2.csv", "/home/user/cov2.txt") in observed

    dataset_lines = [
        "1.2,3.4,5.6", "2.5,4.1,6.8", "3.1,5.5,7.2", "4.8,6.2,8.9", "5.0,7.0,9.1",
        "6.3,8.4,10.5", "7.2,9.1,11.2", "8.5,10.6,12.8", "9.1,11.5,13.4", "10.4,12.0,14.7"
    ]
    with open("/home/user/split1.csv", "r", encoding="utf-8") as f:
        assert f.read().splitlines() == dataset_lines[:5]
    with open("/home/user/split2.csv", "r", encoding="utf-8") as f:
        assert f.read().splitlines() == dataset_lines[5:]

    test_cov_outputs()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
