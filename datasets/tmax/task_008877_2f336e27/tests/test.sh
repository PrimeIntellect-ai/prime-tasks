#!/bin/bash
set +e
mkdir -p /logs/verifier
reward=0

# Restore the supplied ETL program with verification-only tracing so the verifier
# can prove that pipeline.sh invokes it with the required environment.
cat << 'PY_EOF' > /home/user/scripts/extract.py
import json
import os
import sys
import pandas as pd

if len(sys.argv) != 3:
    print("Usage: extract.py <input.csv> <output.csv>")
    sys.exit(1)

with open("/tmp/extract_trace.jsonl", "a") as trace:
    trace.write(json.dumps({
        "input": os.path.realpath(sys.argv[1]),
        "output": os.path.realpath(sys.argv[2]),
        "mode": os.environ.get("PROCESSING_MODE"),
        "executable": sys.executable,
    }) + "\n")

if os.environ.get('PROCESSING_MODE') != 'strict':
    df = pd.DataFrame()
else:
    df = pd.read_csv(sys.argv[1])
    df['feature_alpha'] = df['feature_alpha'] * 2.0

df.to_csv(sys.argv[2], index=False)
PY_EOF
chmod +x /home/user/scripts/extract.py

# First exercise the pipeline from a clean state using the original inputs.
cat << 'CSV_EOF' > /home/user/raw_data/dataset1.csv
id,feature_alpha,feature_beta,feature_gamma,target
1,0.5,1.2,0.9,0
2,0.1,0.8,0.3,1
CSV_EOF
cat << 'CSV_EOF' > /home/user/raw_data/dataset2.csv
id,feature_alpha,feature_beta,feature_gamma,target
3,0.9,1.1,0.1,1
4,0.4,0.5,0.8,0
CSV_EOF
rm -rf /home/user/venv /home/user/processed
rm -f /home/user/final_features.csv /home/user/row_count.txt /tmp/extract_trace.jsonl

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess


def test_pipeline_sh_exists_and_executable():
    file_path = "/home/user/pipeline.sh"
    assert os.path.isfile(file_path), f"File {file_path} is missing."
    st = os.stat(file_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {file_path} is not executable."


def test_venv_exists():
    venv_path = "/home/user/venv"
    assert os.path.isdir(venv_path), f"Virtual environment directory {venv_path} is missing."
    python_bin = os.path.join(venv_path, "bin", "python")
    assert os.path.isfile(python_bin), f"Python executable in venv is missing at {python_bin}."


def test_pandas_is_installed_in_venv():
    python_bin = "/home/user/venv/bin/python"
    result = subprocess.run(
        [python_bin, "-c", "import os,pandas; print(os.path.realpath(pandas.__file__))"],
        text=True, capture_output=True
    )
    assert result.returncode == 0, result.stderr
    pandas_path = result.stdout.strip()
    assert pandas_path.startswith("/home/user/venv/"), (
        f"pandas was not installed inside the virtual environment: {pandas_path}"
    )


def test_processed_dir_exists():
    processed_dir = "/home/user/processed"
    assert os.path.isdir(processed_dir), f"Directory {processed_dir} is missing."


def test_processed_files():
    expected = {
        "/home/user/processed/dataset1_proc.csv": [
            "id,feature_alpha,feature_beta,feature_gamma,target",
            "1,1.0,1.2,0.9,0",
            "2,0.2,0.8,0.3,1",
        ],
        "/home/user/processed/dataset2_proc.csv": [
            "id,feature_alpha,feature_beta,feature_gamma,target",
            "3,1.8,1.1,0.1,1",
            "4,0.8,0.5,0.8,0",
        ],
    }
    for path, expected_lines in expected.items():
        assert os.path.isfile(path), f"Processed file {path} is missing."
        with open(path) as f:
            lines = [line.strip() for line in f if line.strip()]
        assert lines == expected_lines, f"Unexpected processed data in {path}: {lines}"


def test_extract_was_run_in_strict_mode_for_both_inputs():
    with open("/tmp/extract_trace.jsonl") as f:
        calls = [json.loads(line) for line in f if line.strip()]
    expected_calls = {
        ("/home/user/raw_data/dataset1.csv", "/home/user/processed/dataset1_proc.csv"),
        ("/home/user/raw_data/dataset2.csv", "/home/user/processed/dataset2_proc.csv"),
    }
    observed = {(c["input"], c["output"]) for c in calls if c.get("mode") == "strict"}
    assert expected_calls <= observed, f"Required strict-mode extract.py calls not found: {calls}"


def test_final_features_csv():
    file_path = "/home/user/final_features.csv"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "id,feature_alpha,feature_beta,target",
        "1,1.0,1.2,0",
        "2,0.2,0.8,1",
        "3,1.8,1.1,1",
        "4,0.8,0.5,0"
    ]

    assert len(lines) == 5, f"Expected 5 lines in {file_path}, but got {len(lines)}."
    assert lines[0] == expected_lines[0], f"Header mismatch in {file_path}. Expected {expected_lines[0]} but got {lines[0]}."
    data_lines = sorted(lines[1:])
    expected_data = sorted(expected_lines[1:])
    assert data_lines == expected_data, f"Data mismatch in {file_path}. Expected {expected_data} but got {data_lines}."


def test_row_count_txt():
    file_path = "/home/user/row_count.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing."
    with open(file_path, "r") as f:
        content = f.read().strip()
    assert content == "4", f"Expected row count to be '4', but got '{content}'."
TEST_EOF

first_ok=0
if timeout 240 /home/user/pipeline.sh; then
    if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short; then
        first_ok=1
    fi
fi

# Re-run on unpredictable inputs and derive all expected outputs from those inputs.
if [ "$first_ok" -eq 1 ]; then
    python3 - << 'PY_EOF'
import csv
import secrets

base = secrets.randbelow(100000) + 1000
rows1 = [
    [base, 2, 1.25, 8.5, 0],
    [base + 1, 7, 3.75, 2.5, 1],
    [base + 2, 11, 9.5, 1.5, 0],
]
rows2 = [
    [base + 10, 3, 4.25, 7.5, 1],
    [base + 11, 13, 6.5, 3.5, 0],
]
header = ["id", "feature_alpha", "feature_beta", "feature_gamma", "target"]
for path, rows in [
    ("/home/user/raw_data/dataset1.csv", rows1),
    ("/home/user/raw_data/dataset2.csv", rows2),
]:
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)
PY_EOF
    rm -rf /home/user/processed
    rm -f /home/user/final_features.csv /home/user/row_count.txt /tmp/extract_trace.jsonl

    cat << 'TEST_EOF' > /tmp/test_dynamic_pipeline.py
import json
import os
import pandas as pd


def sorted_by_id(frame):
    return frame.sort_values("id").reset_index(drop=True)


def test_dynamic_processed_and_final_outputs():
    raw_paths = [
        "/home/user/raw_data/dataset1.csv",
        "/home/user/raw_data/dataset2.csv",
    ]
    processed_paths = [
        "/home/user/processed/dataset1_proc.csv",
        "/home/user/processed/dataset2_proc.csv",
    ]

    expected_processed = []
    for raw_path, processed_path in zip(raw_paths, processed_paths):
        raw = pd.read_csv(raw_path)
        expected = raw.copy()
        expected["feature_alpha"] = expected["feature_alpha"] * 2.0
        actual = pd.read_csv(processed_path)
        assert list(actual.columns) == list(expected.columns)
        pd.testing.assert_frame_equal(
            sorted_by_id(actual), sorted_by_id(expected),
            check_dtype=False, check_exact=False, rtol=1e-10, atol=1e-10
        )
        expected_processed.append(expected)

    expected_final = pd.concat(expected_processed, ignore_index=True)[
        ["id", "feature_alpha", "feature_beta", "target"]
    ]
    actual_final = pd.read_csv("/home/user/final_features.csv")
    assert list(actual_final.columns) == ["id", "feature_alpha", "feature_beta", "target"]
    pd.testing.assert_frame_equal(
        sorted_by_id(actual_final), sorted_by_id(expected_final),
        check_dtype=False, check_exact=False, rtol=1e-10, atol=1e-10
    )

    with open("/home/user/row_count.txt") as f:
        count_text = f.read().strip()
    assert count_text.isdigit()
    assert int(count_text) == len(expected_final)


def test_dynamic_run_invoked_extract_in_strict_mode():
    with open("/tmp/extract_trace.jsonl") as f:
        calls = [json.loads(line) for line in f if line.strip()]
    expected_calls = {
        ("/home/user/raw_data/dataset1.csv", "/home/user/processed/dataset1_proc.csv"),
        ("/home/user/raw_data/dataset2.csv", "/home/user/processed/dataset2_proc.csv"),
    }
    observed = {(c["input"], c["output"]) for c in calls if c.get("mode") == "strict"}
    assert expected_calls <= observed, f"Required strict-mode extract.py calls not found: {calls}"
TEST_EOF

    if timeout 240 /home/user/pipeline.sh; then
        if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_dynamic_pipeline.py -x --tb=short; then
            reward=1
        fi
    fi
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0
