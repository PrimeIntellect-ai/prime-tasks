#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import shutil
import stat
import subprocess
import tempfile

EXTRACT = "/home/user/extract.sh"
SUMMARY = "/home/user/summary.csv"
SOURCE = "/home/user/analyze_runs.c"
BINARY = "/home/user/analyze_runs"

EXPECTED_LINES = [
    "run_1,0.85,120",
    "run_2,0.92,150",
    "run_3,0.88,110",
    "run_4,0.95,200",
    "run_5,0.79,90",
]


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_extract_script_exists_and_executable():
    script_path = EXTRACT
    assert os.path.isfile(script_path), f"Bash script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Bash script {script_path} is not executable."


def test_summary_csv_content():
    summary_path = SUMMARY
    assert os.path.isfile(summary_path), f"Summary CSV {summary_path} does not exist."
    actual_lines = read_nonempty_lines(summary_path)
    assert actual_lines == EXPECTED_LINES, (
        f"Content of {summary_path} is incorrect or not sorted properly. "
        f"Expected: {EXPECTED_LINES}, Got: {actual_lines}"
    )


def test_analyze_runs_c_and_executable():
    c_path = SOURCE
    exe_path = BINARY

    assert os.path.isfile(c_path), f"C source file {c_path} does not exist."
    assert os.path.isfile(exe_path), f"Compiled executable {exe_path} does not exist."
    st = os.stat(exe_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Compiled file {exe_path} is not executable."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Compiled file {exe_path} is not an ELF executable."


def test_best_match_output():
    best_match_path = "/home/user/best_match.txt"
    assert os.path.isfile(best_match_path), f"Output file {best_match_path} does not exist."

    with open(best_match_path, "r") as f:
        content = f.read().strip()

    assert content == "run_2", f"Expected closest match 'run_2', but got '{content}'."


def test_posterior_output():
    posterior_path = "/home/user/posterior.txt"
    assert os.path.isfile(posterior_path), f"Output file {posterior_path} does not exist."

    with open(posterior_path, "r") as f:
        content = f.read().strip()

    expected_val = "0.8028"
    assert content == expected_val, f"Expected posterior probability '{expected_val}', but got '{content}'."


def test_extract_executes_on_original_inputs():
    result = subprocess.run([EXTRACT], cwd="/home/user", text=True, capture_output=True, timeout=10)
    assert result.returncode == 0, f"extract.sh failed: {result.stderr}"
    assert os.path.isfile(SUMMARY), "extract.sh did not create summary.csv"
    assert read_nonempty_lines(SUMMARY) == EXPECTED_LINES


def test_extract_on_additional_inputs():
    experiments = "/home/user/experiments"
    backup = tempfile.mkdtemp(prefix="experiments_backup_")
    os.rmdir(backup)
    token = secrets.token_hex(5)
    expected = {
        f"run_{token}_zeta": (0.94731, 203.25),
        f"run_{token}_alpha": (0.81327, 77.5),
        f"run_{token}_middle": (0.90246, 126.75),
        f"run_{token}_beta": (0.87519, 98.0),
    }

    os.rename(experiments, backup)
    os.mkdir(experiments)
    try:
        for index, (run_id, (accuracy, latency)) in enumerate(expected.items()):
            with open(os.path.join(experiments, run_id + ".csv"), "w") as f:
                f.write("epoch,loss,accuracy,latency_ms\n")
                f.write(f"1,0.9,{accuracy - 0.2:.5f},{latency + 7}\n")
                f.write(f"2,0.5,{accuracy - 0.1:.5f},{latency + 3}\n")
                f.write(f"3,0.2,{accuracy:.5f},{latency}\n")

        result = subprocess.run([EXTRACT], cwd="/home/user", text=True, capture_output=True, timeout=10)
        assert result.returncode == 0, f"extract.sh failed on additional inputs: {result.stderr}"
        lines = read_nonempty_lines(SUMMARY)
        assert len(lines) == len(expected), f"Expected {len(expected)} summary rows, got {lines}"

        parsed_ids = []
        for line in lines:
            fields = line.split(",")
            assert len(fields) == 3, f"Malformed summary row: {line}"
            run_id, accuracy_text, latency_text = fields
            assert run_id in expected, f"Unexpected run ID or header in summary: {run_id}"
            parsed_ids.append(run_id)
            expected_accuracy, expected_latency = expected[run_id]
            assert math.isclose(float(accuracy_text), expected_accuracy, rel_tol=0, abs_tol=1e-10)
            assert math.isclose(float(latency_text), expected_latency, rel_tol=0, abs_tol=1e-10)

        assert parsed_ids == sorted(expected), f"Summary is not alphabetically sorted: {parsed_ids}"
    finally:
        if os.path.exists(experiments):
            shutil.rmtree(experiments)
        os.rename(backup, experiments)
        subprocess.run([EXTRACT], cwd="/home/user", text=True, capture_output=True, timeout=10)

    assert read_nonempty_lines(SUMMARY) == EXPECTED_LINES


def compile_submitted_source():
    output = os.path.join(tempfile.mkdtemp(prefix="compiled_source_"), "analyze_runs")
    result = subprocess.run(
        ["gcc", "-O2", "-o", output, SOURCE, "-lm"],
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert result.returncode == 0, f"analyze_runs.c does not compile: {result.stderr}"
    return output


def exercise_analysis_program(program):
    rows = [
        ("run_orchid", 0.8123, 73.5),
        ("run_cobalt", 0.9342, 141.7),
        ("run_amber", 0.9011, 109.2),
        ("run_slate", 0.7654, 188.3),
        ("run_ivory", 0.8827, 126.4),
    ]
    with tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False) as f:
        csv_path = f.name
        for run_id, accuracy, latency in rows:
            f.write(f"{run_id},{accuracy},{latency}\n")

    try:
        targets = [(0.91, 135.0), (0.80, 79.0), (0.89, 111.0)]
        for target_accuracy, target_latency in targets:
            expected = min(
                rows,
                key=lambda row: ((row[1] - target_accuracy) * 100) ** 2
                + (row[2] - target_latency) ** 2,
            )[0]
            result = subprocess.run(
                [program, "similarity", csv_path, str(target_accuracy), str(target_latency)],
                text=True,
                capture_output=True,
                timeout=10,
            )
            assert result.returncode == 0, f"Similarity mode failed: {result.stderr}"
            assert result.stdout.strip() == expected, (
                f"Similarity mode returned {result.stdout!r}; expected only {expected!r}"
            )

        cases = [
            (0.17, 0.83, 0.24),
            (0.61, 0.72, 0.31),
            (0.42, 0.93, 0.08),
            (0.08, 0.55, 0.67),
        ]
        for prior, success, failure in cases:
            posterior = (prior * success) / ((prior * success) + ((1 - prior) * failure))
            expected = f"{posterior:.4f}"
            result = subprocess.run(
                [program, "bayes", str(prior), str(success), str(failure)],
                text=True,
                capture_output=True,
                timeout=10,
            )
            assert result.returncode == 0, f"Bayes mode failed: {result.stderr}"
            assert result.stdout.strip() == expected, (
                f"Bayes mode returned {result.stdout!r}; expected only {expected!r}"
            )
    finally:
        os.unlink(csv_path)


def test_installed_analysis_executable_on_additional_inputs():
    exercise_analysis_program(BINARY)


def test_submitted_c_source_on_additional_inputs():
    compiled = compile_submitted_source()
    try:
        exercise_analysis_program(compiled)
    finally:
        shutil.rmtree(os.path.dirname(compiled), ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
