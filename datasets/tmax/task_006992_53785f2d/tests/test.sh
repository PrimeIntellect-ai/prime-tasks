#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shlex
import shutil
import stat
import subprocess
import tempfile

from scipy.stats import ttest_ind

PROJECT = "/home/user/bio_project"
EXECUTABLE = os.path.join(PROJECT, "src", "gc_calc")
PIPELINE = os.path.join(PROJECT, "run_pipeline.py")
REPORT = os.path.join(PROJECT, "report.txt")
DATA = os.path.join(PROJECT, "data")
GOLDEN = os.path.join(DATA, "golden_gc.json")


def run_gc(path):
    result = subprocess.run(
        [EXECUTABLE, path], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, result.stderr
    return float(result.stdout.strip())


def expected_gc(sequence):
    bases = [c.upper() for c in sequence if c.upper() in "ACGT"]
    return 100.0 * sum(c in "GC" for c in bases) / len(bases)


def test_executable_exists():
    assert os.path.exists(EXECUTABLE), f"Executable {EXECUTABLE} not found. Did you compile the C code?"
    assert os.path.isfile(EXECUTABLE), f"{EXECUTABLE} is not a regular file."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "gc_calc is not a compiled ELF executable."


def test_gc_calc_behavior():
    samples = [
        "GgCcAaTtNn",
        "AAAA\nCCCC\nGGTA",
        "acgtacgtacgt\nNNNN\nggg",
    ]
    for sequence in samples:
        fd, path = tempfile.mkstemp(suffix=".fasta")
        try:
            with os.fdopen(fd, "w") as f:
                f.write(">generated_test\n" + sequence + "\n")
            actual = run_gc(path)
            assert abs(actual - expected_gc(sequence)) <= 0.0001
        finally:
            os.unlink(path)


def test_pipeline_executes_tool_and_handles_regression_failure():
    assert os.path.exists(PIPELINE), f"Pipeline script {PIPELINE} not found."
    assert os.path.isfile(PIPELINE), f"{PIPELINE} is not a regular file."
    assert os.path.exists(GOLDEN), f"Data file {GOLDEN} is missing."

    with open(GOLDEN, "rb") as f:
        original_golden_bytes = f.read()
    original_mode = stat.S_IMODE(os.stat(EXECUTABLE).st_mode)

    backup_fd, backup_path = tempfile.mkstemp(prefix="gc_calc.real.")
    os.close(backup_fd)
    shutil.copy2(EXECUTABLE, backup_path)
    log_fd, invocation_log = tempfile.mkstemp(prefix="gc_invocations.")
    os.close(log_fd)

    wrapper = "#!/bin/sh\nprintf '%s\\t%s\\n' \"$PWD\" \"$1\" >> {}\nexec {} \"$@\"\n".format(
        shlex.quote(invocation_log), shlex.quote(backup_path)
    )

    def run_pipeline():
        return subprocess.run(
            ["python3", PIPELINE],
            cwd=PROJECT,
            capture_output=True,
            text=True,
            timeout=60,
        )

    try:
        with open(EXECUTABLE, "w") as f:
            f.write(wrapper)
        os.chmod(EXECUTABLE, 0o755)

        if os.path.exists(REPORT):
            os.unlink(REPORT)
        first = run_pipeline()
        assert first.returncode == 0, first.stdout + first.stderr
        assert os.path.exists(REPORT), "Running run_pipeline.py did not create report.txt."

        with open(GOLDEN) as f:
            golden = json.load(f)
        required = {os.path.realpath(os.path.join(DATA, name)) for name in golden}
        invoked = set()
        with open(invocation_log) as f:
            for line in f:
                cwd, argument = line.rstrip("\n").split("\t", 1)
                invoked.add(os.path.realpath(argument if os.path.isabs(argument) else os.path.join(cwd, argument)))
        missing = required - invoked
        assert not missing, f"run_pipeline.py did not execute gc_calc for: {sorted(missing)}"

        bad_golden = dict(golden)
        first_name = sorted(bad_golden)[0]
        bad_golden[first_name] = float(bad_golden[first_name]) + 1.0
        with open(GOLDEN, "w") as f:
            json.dump(bad_golden, f)
        if os.path.exists(REPORT):
            os.unlink(REPORT)
        run_pipeline()
        assert os.path.exists(REPORT), "Regression failure did not create report.txt."
        with open(REPORT) as f:
            failure_report = f.read().strip()
        assert failure_report == "Regression: FAIL", "Pipeline did not stop with Regression: FAIL on a mismatched golden value."

        with open(GOLDEN, "wb") as f:
            f.write(original_golden_bytes)
        if os.path.exists(REPORT):
            os.unlink(REPORT)
        final = run_pipeline()
        assert final.returncode == 0, final.stdout + final.stderr
    finally:
        with open(GOLDEN, "wb") as f:
            f.write(original_golden_bytes)
        shutil.copy2(backup_path, EXECUTABLE)
        os.chmod(EXECUTABLE, original_mode)
        os.unlink(backup_path)
        os.unlink(invocation_log)


def test_report_content():
    assert os.path.exists(REPORT), f"Report file {REPORT} not found."
    with open(REPORT) as f:
        lines = [line.strip() for line in f.read().strip().split("\n") if line.strip()]
    assert len(lines) >= 4, "report.txt is missing required lines."

    assert os.path.exists(GOLDEN), f"Data file {GOLDEN} is missing."
    with open(GOLDEN) as f:
        golden = json.load(f)

    case_gcs = [v for k, v in golden.items() if k.startswith("case_")]
    control_gcs = [v for k, v in golden.items() if k.startswith("control_")]
    expected_case_mean = sum(case_gcs) / len(case_gcs)
    expected_control_mean = sum(control_gcs) / len(control_gcs)
    expected_p = ttest_ind(case_gcs, control_gcs, equal_var=True).pvalue

    expected_lines = [
        "Regression: PASS",
        f"Control Mean: {expected_control_mean:.4f}",
        f"Case Mean: {expected_case_mean:.4f}",
        f"P-value: {expected_p:.4f}",
    ]
    for i, expected in enumerate(expected_lines):
        assert lines[i] == expected, f"Mismatch at line {i+1} in report.txt. Expected '{expected}', got '{lines[i]}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
