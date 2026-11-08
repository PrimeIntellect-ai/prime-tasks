#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import pytest

SCRIPT = "/home/user/profile_run.sh"
SOURCE = "/home/user/aggregate_stats.c"
METRICS = "/home/user/metrics.dat"
RESULTS = "/home/user/profile_results.txt"
BINARY = "/home/user/aggregate_stats"


def clean_env():
    env = os.environ.copy()
    env.pop("METRICS_FILE", None)
    env.pop("METRIC_FILE", None)
    return env


def read_result():
    assert os.path.isfile(RESULTS), f"The results file {RESULTS} was not generated. Did you run the script?"
    with open(RESULTS, "r") as f:
        return f.read().strip()


def test_script_executes_compiles_and_handles_derived_input():
    assert os.path.isfile(SCRIPT), f"Missing file: {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable"

    with open(SCRIPT, "rb") as f:
        assert f.read(2) == b"#!", f"{SCRIPT} is not a shell script"

    with open(METRICS, "rb") as f:
        original_metrics = f.read()

    values = [secrets.randbelow(9000) + 1000 for _ in range(11)]
    while sum(values[:10]) == 550:
        values = [secrets.randbelow(9000) + 1000 for _ in range(11)]
    expected = f"Total: {sum(values[:10])}"

    final_run = None
    try:
        with open(METRICS, "w") as f:
            f.write("".join(f"{value}\n" for value in values))

        for path in (RESULTS, BINARY):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

        run = subprocess.run(
            [SCRIPT], env=clean_env(), stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert run.returncode == 0, (
            f"{SCRIPT} exited with code {run.returncode}\nstdout:\n{run.stdout}\nstderr:\n{run.stderr}"
        )
        assert read_result() == expected, (
            f"Expected derived result '{expected}', but got '{read_result()}'"
        )

        assert os.path.isfile(BINARY), "The script did not compile /home/user/aggregate_stats"
        assert os.access(BINARY, os.X_OK), "The compiled aggregate_stats is not executable"
        with open(BINARY, "rb") as f:
            assert f.read(4) == b"\x7fELF", "aggregate_stats is not a compiled ELF program"

        sections = subprocess.run(
            ["readelf", "--sections", BINARY], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=10
        )
        assert sections.returncode == 0 and ".debug_info" in sections.stdout, (
            "The program produced by profile_run.sh does not contain debugging symbols; compile it with -g"
        )

        sanitizer_binary = "/tmp/aggregate_stats_asan"
        compile_asan = subprocess.run(
            ["gcc", "-g", "-fsanitize=address", "-fno-omit-frame-pointer",
             "-o", sanitizer_binary, SOURCE],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert compile_asan.returncode == 0, (
            f"aggregate_stats.c failed to compile with memory checking:\n{compile_asan.stderr}"
        )
        asan_env = clean_env()
        asan_env["METRICS_FILE"] = METRICS
        asan_env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
        checked_run = subprocess.run(
            [sanitizer_binary], env=asan_env, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert checked_run.returncode == 0, (
            "aggregate_stats still has a memory error when reading 11 metrics. "
            f"Exit code: {checked_run.returncode}\nstdout:\n{checked_run.stdout}\nstderr:\n{checked_run.stderr}"
        )
        assert read_result() == expected
    finally:
        with open(METRICS, "wb") as f:
            f.write(original_metrics)
        try:
            os.unlink(RESULTS)
        except FileNotFoundError:
            pass
        final_run = subprocess.run(
            [SCRIPT], env=clean_env(), stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=30
        )

    assert final_run.returncode == 0, (
        f"Final execution of {SCRIPT} exited with code {final_run.returncode}\n"
        f"stdout:\n{final_run.stdout}\nstderr:\n{final_run.stderr}"
    )


def test_results_file_exists_and_correct():
    results_file = "/home/user/profile_results.txt"
    assert os.path.isfile(results_file), f"The results file {results_file} was not generated. Did you run the script?"

    with open(results_file, "r") as f:
        content = f.read().strip()

    assert content == "Total: 550", f"Expected 'Total: 550' in {results_file}, but got '{content}'"


def test_sh_file_fixed():
    sh_file = "/home/user/profile_run.sh"
    assert os.path.isfile(sh_file), f"Missing file: {sh_file}"

    with open(sh_file, "r") as f:
        content = f.read()

    assert "METRICS_FILE" in content, "The environment variable in profile_run.sh was not corrected to METRICS_FILE"
    assert "METRIC_FILE" not in content or "export METRICS_FILE=" in content, "The typo METRIC_FILE is still present or not fixed properly."


def test_c_file_fixed():
    c_file = "/home/user/aggregate_stats.c"
    assert os.path.isfile(c_file), f"Missing file: {c_file}"

    with open(c_file, "r") as f:
        content = f.read()

    assert "count <= 10" not in content, "The off-by-one error 'count <= 10' is still present in aggregate_stats.c"
    assert "while" in content and "fscanf" in content, "The reading loop was removed from aggregate_stats.c"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
