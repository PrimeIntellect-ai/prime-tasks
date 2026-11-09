#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess
import tempfile

PIPELINE_DIR = "/home/user/pipeline"
DATA_CSV = os.path.join(PIPELINE_DIR, "data.csv")
CLEANER_CPP = os.path.join(PIPELINE_DIR, "cleaner.cpp")
RUN_SCRIPT = os.path.join(PIPELINE_DIR, "run_pipeline.sh")
CLEANER_BIN = os.path.join(PIPELINE_DIR, "cleaner")
MODEL_PARAMS = os.path.join(PIPELINE_DIR, "model_params.txt")


def parse_params(path):
    with open(path, "r") as f:
        content = f.read().strip()
    number = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
    match = re.fullmatch(rf"m=({number}),c=({number})", content)
    assert match is not None, f"Could not parse model parameters. Content: {content!r}"
    values = (float(match.group(1)), float(match.group(2)))
    assert all(math.isfinite(v) for v in values), "Model parameters must be finite."
    return values


def write_generated_dataset(path, slope, intercept, center):
    rows = ["id,feature,target"]
    record_id = 1
    # A dense central population with two balanced, invalid outliers. The valid
    # records follow a line selected at verification time.
    for i in range(36):
        x = center + (i % 7)
        y = slope * x + intercept
        rows.append(f"{record_id},{x},{y}")
        record_id += 1
    rows.append(f"{record_id},{center + 60},777")
    rows.append(f"{record_id + 1},{center - 60},-333")
    with open(path, "w") as f:
        f.write("\n".join(rows) + "\n")


def run_script():
    env = os.environ.copy()
    env.pop("DATASET_PATH", None)
    return subprocess.run(
        [RUN_SCRIPT], cwd=PIPELINE_DIR, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )


def test_cleaner_cpp_fixed():
    assert os.path.isfile(CLEANER_CPP), f"File {CLEANER_CPP} does not exist."
    with open(CLEANER_CPP, "r") as f:
        content = f.read()

    # The bug was `int total_sum = 0;` which caused integer truncation/overflow.
    # It should be changed to a floating point type (double or float).
    assert "int total_sum" not in content, "The bug 'int total_sum' is still present in cleaner.cpp."
    assert "double total_sum" in content or "float total_sum" in content or "auto total_sum = 0.0" in content, \
        "total_sum must be declared as a floating-point type (e.g., double) in cleaner.cpp."


def test_run_script_fixed():
    assert os.path.isfile(RUN_SCRIPT), f"File {RUN_SCRIPT} does not exist."
    with open(RUN_SCRIPT, "r") as f:
        content = f.read()

    # The run script must export DATASET_PATH or pass it directly to the executable.
    assert "DATASET_PATH=" in content, "DATASET_PATH is not being set in run_pipeline.sh."
    assert "data.csv" in content, "The path to data.csv is not provided in run_pipeline.sh."


def test_pipeline_is_actually_compiled_and_executed():
    assert os.access(RUN_SCRIPT, os.X_OK), "run_pipeline.sh is not executable."
    for path in (CLEANER_BIN, MODEL_PARAMS):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = run_script()
    assert result.returncode == 0, (
        f"run_pipeline.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(CLEANER_BIN), "The runner did not compile cleaner.cpp."
    assert os.access(CLEANER_BIN, os.X_OK), "The compiled cleaner is not executable."
    with open(CLEANER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The generated cleaner is not a compiled ELF executable."
    assert os.path.isfile(MODEL_PARAMS), "Running the pipeline did not generate model_params.txt."


def test_model_params_output():
    assert os.path.isfile(MODEL_PARAMS), f"Output file {MODEL_PARAMS} was not generated."

    with open(MODEL_PARAMS, "r") as f:
        content = f.read().strip()

    assert content != "", f"File {MODEL_PARAMS} is empty. The pipeline might have failed silently."

    # Parse m and c values
    match = re.search(r"m=([0-9\.\-]+),c=([0-9\.\-]+)", content)
    assert match is not None, f"Could not parse 'm' and 'c' values from {MODEL_PARAMS}. Content: {content}"

    m_val = float(match.group(1))
    c_val = float(match.group(2))

    # The expected values based on the cleaned dataset are m=2.0 and c=0.0
    assert abs(m_val - 2.0) < 1e-5, f"Expected m to be approximately 2.0, but got {m_val}."
    assert abs(c_val - 0.0) < 1e-5, f"Expected c to be approximately 0.0, but got {c_val}."


def test_pipeline_and_cleaner_on_derived_inputs():
    with open(DATA_CSV, "rb") as f:
        original_data = f.read()
    with open(MODEL_PARAMS, "rb") as f:
        original_model = f.read()

    slope = secrets.choice([-5, -3, -1, 1, 3, 4, 6])
    intercept = secrets.choice([-17, -9, -2, 4, 11, 19])
    center = secrets.choice([-20, -11, -3, 5, 13, 21])

    try:
        # Exercise the complete runner on data whose answer is selected by the verifier.
        write_generated_dataset(DATA_CSV, slope, intercept, center)
        if os.path.exists(MODEL_PARAMS):
            os.remove(MODEL_PARAMS)
        result = run_script()
        assert result.returncode == 0, (
            f"run_pipeline.sh failed on a valid generated dataset.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        actual_m, actual_c = parse_params(MODEL_PARAMS)
        assert abs(actual_m - slope) < 1e-5, f"Expected generated slope {slope}, got {actual_m}."
        assert abs(actual_c - intercept) < 1e-5, f"Expected generated intercept {intercept}, got {actual_c}."

        # Invoke the compiled artifact directly with a different DATASET_PATH to
        # verify that cleaner.cpp reads the configured path rather than canned data.
        slope2 = secrets.choice([v for v in [-6, -4, -2, 2, 5, 7] if v != slope])
        intercept2 = secrets.choice([-23, -8, 3, 14, 27])
        center2 = secrets.choice([-16, -7, 2, 10, 18])
        fd, alternate_path = tempfile.mkstemp(prefix="pipeline-data-", suffix=".csv")
        os.close(fd)
        try:
            write_generated_dataset(alternate_path, slope2, intercept2, center2)
            if os.path.exists(MODEL_PARAMS):
                os.remove(MODEL_PARAMS)
            env = os.environ.copy()
            env["DATASET_PATH"] = alternate_path
            direct = subprocess.run(
                [CLEANER_BIN], cwd=PIPELINE_DIR, env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
            )
            assert direct.returncode == 0, (
                f"Compiled cleaner failed on DATASET_PATH input.\n"
                f"stdout:\n{direct.stdout}\nstderr:\n{direct.stderr}"
            )
            actual_m, actual_c = parse_params(MODEL_PARAMS)
            assert abs(actual_m - slope2) < 1e-5, f"Expected direct slope {slope2}, got {actual_m}."
            assert abs(actual_c - intercept2) < 1e-5, f"Expected direct intercept {intercept2}, got {actual_c}."
        finally:
            if os.path.exists(alternate_path):
                os.remove(alternate_path)
    finally:
        with open(DATA_CSV, "wb") as f:
            f.write(original_data)
        with open(MODEL_PARAMS, "wb") as f:
            f.write(original_model)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
