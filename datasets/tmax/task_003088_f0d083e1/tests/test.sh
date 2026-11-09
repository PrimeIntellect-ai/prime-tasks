#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import uuid
from pathlib import Path

GO_PATH = Path("/home/user/bayes_check.go")
SCRIPT_PATH = Path("/home/user/run_pipeline.sh")
CSV_PATH = Path("/home/user/dataset_stats.csv")
RESULT_PATHS = [
    Path("/home/user/results.txt"),
    Path("/home/user/results2.txt"),
    Path("/home/user/pipeline.log"),
]


def clear_outputs():
    for path in RESULT_PATHS:
        if path.exists():
            path.unlink()


def run_pipeline():
    subprocess.run(
        [str(SCRIPT_PATH)],
        cwd="/home/user",
        check=True,
        timeout=120,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def test_00_artifacts_execute_and_pipeline_uses_go_program():
    assert GO_PATH.exists(), f"Required file is missing: {GO_PATH}"
    assert GO_PATH.is_file(), f"Path is not a file: {GO_PATH}"
    assert SCRIPT_PATH.exists(), f"Required file is missing: {SCRIPT_PATH}"
    assert SCRIPT_PATH.is_file(), f"Path is not a file: {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"File is not executable: {SCRIPT_PATH}"

    original_go = GO_PATH.read_bytes()
    original_csv = CSV_PATH.read_bytes()
    binary_path = Path("/tmp/verifier_bayes_check")

    try:
        # Compile and exercise the submitted Go program on verifier-generated data.
        nonce = uuid.uuid4().hex[:12]
        rows = [
            (f"hidden_{nonce}_a", 0.37, 0.82, 0.23),
            (f"hidden_{nonce}_b", 0.73, 0.41, 0.64),
            (f"hidden_{nonce}_c", 0.18, 0.57, 0.31),
        ]
        csv_text = "dataset_id,prior_clean,likelihood_clean,likelihood_corrupt\n"
        csv_text += "".join(f"{i},{p},{lc},{lx}\n" for i, p, lc, lx in rows)
        CSV_PATH.write_text(csv_text)

        subprocess.run(
            ["go", "build", "-o", str(binary_path), str(GO_PATH)],
            check=True,
            timeout=120,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        completed = subprocess.run(
            [str(binary_path)],
            check=True,
            timeout=30,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        expected = []
        for dataset_id, prior, clean, corrupt in rows:
            posterior = clean * prior / (clean * prior + corrupt * (1.0 - prior))
            expected.append(f"{dataset_id},{posterior:.6f}")
        assert completed.stdout.strip().splitlines() == expected

        # Replace the source temporarily with a nonce-bearing program. The pipeline
        # must compile and run the current Go source twice rather than fabricate files.
        marker1 = f"pipeline_{uuid.uuid4().hex}_a"
        marker2 = f"pipeline_{uuid.uuid4().hex}_b"
        injected = f'''package main
import "fmt"
func main() {{
    fmt.Println("{marker1},0.125000")
    fmt.Println("{marker2},0.375000")
}}
'''
        GO_PATH.write_text(injected)
        clear_outputs()
        run_pipeline()

        expected_pipeline = [f"{marker1},0.125000", f"{marker2},0.375000"]
        assert Path("/home/user/results.txt").read_text().strip().splitlines() == expected_pipeline
        assert Path("/home/user/results2.txt").read_text().strip().splitlines() == expected_pipeline
        log = Path("/home/user/pipeline.log").read_text()
        assert "Reproducible: YES" in log
        assert "Sum: 0.500000" in log
    finally:
        GO_PATH.write_bytes(original_go)
        CSV_PATH.write_bytes(original_csv)
        if binary_path.exists():
            binary_path.unlink()

    # Regenerate the required final artifacts from the restored submitted program.
    clear_outputs()
    run_pipeline()


def test_go_program_exists():
    """Test that the Go program exists."""
    go_path = "/home/user/bayes_check.go"
    assert os.path.exists(go_path), f"Required file is missing: {go_path}"
    assert os.path.isfile(go_path), f"Path is not a file: {go_path}"


def test_bash_script_exists_and_executable():
    """Test that the bash script exists and is executable."""
    script_path = "/home/user/run_pipeline.sh"
    assert os.path.exists(script_path), f"Required file is missing: {script_path}"
    assert os.path.isfile(script_path), f"Path is not a file: {script_path}"
    assert os.access(script_path, os.X_OK), f"File is not executable: {script_path}"


def test_results_files():
    """Test that results.txt and results2.txt exist and have the correct contents."""
    results1_path = "/home/user/results.txt"
    results2_path = "/home/user/results2.txt"

    assert os.path.exists(results1_path), f"Required file is missing: {results1_path}"
    assert os.path.exists(results2_path), f"Required file is missing: {results2_path}"

    expected_lines = [
        "ds_001,0.987097",
        "ds_002,0.095238",
        "ds_003,0.999898"
    ]

    with open(results1_path, "r") as f:
        content1 = f.read().strip().splitlines()

    with open(results2_path, "r") as f:
        content2 = f.read().strip().splitlines()

    assert content1 == expected_lines, f"Incorrect contents in {results1_path}"
    assert content2 == expected_lines, f"Incorrect contents in {results2_path}"


def test_pipeline_log():
    """Test that pipeline.log exists and contains the correct outputs."""
    log_path = "/home/user/pipeline.log"
    assert os.path.exists(log_path), f"Required file is missing: {log_path}"

    with open(log_path, "r") as f:
        content = f.read()

    assert "Reproducible: YES" in content, f"'Reproducible: YES' not found in {log_path}"
    assert "Sum: 2.082233" in content, f"'Sum: 2.082233' not found in {log_path}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
