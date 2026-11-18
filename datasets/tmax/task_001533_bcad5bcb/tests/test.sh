#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import random
import re
import subprocess


def test_script_exists():
    script_path = "/home/user/analyze_jitter.py"
    assert os.path.isfile(script_path), f"Student script {script_path} is missing."


def test_script_is_not_reference_copy():
    script_path = "/home/user/analyze_jitter.py"
    oracle_path = "/tests/analyze_jitter_oracle.py"
    with open(script_path, "rb") as student_file, open(oracle_path, "rb") as oracle_file:
        assert student_file.read() != oracle_file.read(), "Student script is byte-identical to the reference implementation."


def test_package_installed():
    result = subprocess.run(
        ["python3", "-c", "import fast_stat_profiler"],
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, (
        "Failed to import fast_stat_profiler. Ensure it is installed system-wide or in the user environment.\n"
        f"Error: {result.stderr}"
    )


def test_makefile_build_process_fixed():
    package_dir = "/app/fast-stat-profiler-1.0"
    makefile_path = os.path.join(package_dir, "Makefile")
    assert os.path.isfile(makefile_path), "Package Makefile is missing."

    env = os.environ.copy()
    env.pop("ALLOW_PROFILER_BUILD", None)

    dry_run = subprocess.run(
        ["make", "-n", "install"],
        cwd=package_dir,
        env=env,
        capture_output=True,
        text=True
    )
    assert dry_run.returncode == 0, f"Makefile install target is invalid:\n{dry_run.stderr}"
    commands = dry_run.stdout + "\n" + dry_run.stderr
    assert re.search(r"\bpython3\s+setup\.py\s+install\b", commands), (
        "The Makefile install target must invoke python3 setup.py install."
    )
    assert re.search(r"ALLOW_PROFILER_BUILD\s*=\s*1", commands), (
        "The Makefile install target must set ALLOW_PROFILER_BUILD=1."
    )

    build = subprocess.run(
        ["make", "install"],
        cwd=package_dir,
        env=env,
        capture_output=True,
        text=True,
        timeout=120
    )
    assert build.returncode == 0, (
        "The repaired Makefile install target failed when executed without the variable pre-set.\n"
        f"Stdout:\n{build.stdout}\nStderr:\n{build.stderr}"
    )


def generate_csv():
    num_rows = random.randint(100, 1000)
    out = io.StringIO()
    writer = csv.writer(out)
    for _ in range(num_rows):
        ts = random.randint(1000000, 9999999)
        rand_val = random.random()
        if rand_val < 0.05:
            val = "NaN"
        elif rand_val < 0.15:
            val = -random.random() * 1000.0
        else:
            val = random.random() * 1000.0
        writer.writerow([ts, val])
    return out.getvalue()


def test_fuzz_equivalence():
    random.seed(42)
    oracle_path = "/tests/analyze_jitter_oracle.py"
    student_path = "/home/user/analyze_jitter.py"

    for i in range(100):
        input_data = generate_csv()

        oracle_res = subprocess.run(
            ["python3", oracle_path],
            input=input_data,
            text=True,
            capture_output=True
        )

        student_res = subprocess.run(
            ["python3", student_path],
            input=input_data,
            text=True,
            capture_output=True
        )

        assert student_res.returncode == 0, (
            f"Student script failed on test case {i}.\n"
            f"Stderr:\n{student_res.stderr}\n"
            f"Stdout:\n{student_res.stdout}"
        )
        assert oracle_res.returncode == 0, f"Oracle failed on test case {i}. Stderr: {oracle_res.stderr}"

        assert student_res.stdout == oracle_res.stdout, (
            f"Output mismatch on test case {i}.\n"
            f"Input data (first 200 chars):\n{input_data[:200]}...\n"
            f"Expected Output:\n{oracle_res.stdout}\n"
            f"Actual Output:\n{student_res.stdout}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
