#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import csv
import random
import subprocess
import tempfile


def test_libsvm_compiled():
    """Verify that libsvm was fixed, compiled, and can train a usable model."""
    makefile_path = "/app/libsvm-3.32/Makefile"
    svm_train_path = "/app/libsvm-3.32/svm-train"
    svm_predict_path = "/app/libsvm-3.32/svm-predict"

    assert os.path.isfile(makefile_path), f"Expected {makefile_path} not found."
    with open(makefile_path, "r", errors="replace") as f:
        makefile_content = f.read()
    assert "fals++" not in makefile_content, "The erroneous compiler setting in the Makefile was not fixed."

    assert os.path.isfile(svm_train_path), f"Expected executable {svm_train_path} not found. Did you compile libsvm?"
    assert os.access(svm_train_path, os.X_OK), f"File {svm_train_path} is not executable."
    assert os.path.isfile(svm_predict_path), f"Expected executable {svm_predict_path} not found. Did you compile libsvm?"
    assert os.access(svm_predict_path, os.X_OK), f"File {svm_predict_path} is not executable."

    for executable in (svm_train_path, svm_predict_path):
        with open(executable, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"{executable} is not a compiled ELF executable."

    with tempfile.TemporaryDirectory() as td:
        training_path = os.path.join(td, "training.libsvm")
        model_path = os.path.join(td, "training.model")
        prediction_path = os.path.join(td, "predictions.txt")
        with open(training_path, "w") as f:
            f.write("-1 1:-2.000000 2:-1.000000\n")
            f.write("-1 1:-1.000000 2:-2.000000\n")
            f.write("1 1:1.000000 2:2.000000\n")
            f.write("1 1:2.000000 2:1.000000\n")

        trained = subprocess.run(
            [svm_train_path, "-q", training_path, model_path],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert trained.returncode == 0, f"svm-train failed: {trained.stderr}"
        assert os.path.isfile(model_path), "svm-train did not create a model file."
        assert os.path.getsize(model_path) > 0, "svm-train created an empty model file."
        with open(model_path, "r", errors="replace") as f:
            model_content = f.read()
        assert "svm_type c_svc" in model_content
        assert "kernel_type rbf" in model_content
        assert "\nSV\n" in model_content

        with open(prediction_path, "w") as pred_out:
            predicted = subprocess.run(
                [svm_predict_path, training_path, model_path, prediction_path],
                stdout=pred_out,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
        assert predicted.returncode == 0, f"svm-predict could not use the trained model: {predicted.stderr}"
        with open(prediction_path, "r") as f:
            predictions = [line.strip() for line in f if line.strip()]
        assert predictions == ["-1", "-1", "1", "1"], f"Unexpected predictions from compiled libsvm: {predictions}"


def test_run_scale_exists_and_executable():
    """Verify that run_scale.sh exists and is executable."""
    run_scale_path = "/home/user/run_scale.sh"
    assert os.path.isfile(run_scale_path), f"Expected script {run_scale_path} not found."
    assert os.access(run_scale_path, os.X_OK), f"Script {run_scale_path} is not executable."


def test_fuzz_equivalence():
    """Fuzz equivalence test against the verification-only oracle."""
    run_scale_path = "/home/user/run_scale.sh"
    oracle_path = "/tests/oracle_scale.py"

    assert os.path.isfile(oracle_path), f"Verification oracle {oracle_path} not found."

    random.seed(42)
    for i in range(50):
        num_rows = random.randint(5, 100)
        num_cols = random.randint(3, 20)

        with tempfile.NamedTemporaryFile(mode="w", delete=False, suffix=".csv", newline="") as f_in:
            input_csv = f_in.name
            writer = csv.writer(f_in)
            for _ in range(num_rows):
                if random.random() < 0.10:
                    row = [0.0] * (num_cols - 1)
                else:
                    row = [random.uniform(-10.0, 10.0) for _ in range(num_cols - 1)]
                row.append(random.randint(0, 5))
                writer.writerow(row)

        agent_out = input_csv + ".agent.txt"
        oracle_out = input_csv + ".oracle.txt"

        try:
            subprocess.run(
                [sys.executable, oracle_path, input_csv, oracle_out],
                check=True,
                capture_output=True,
                timeout=30,
            )
            agent_proc = subprocess.run(
                [run_scale_path, input_csv, agent_out],
                capture_output=True,
                text=True,
                timeout=30,
            )
            assert agent_proc.returncode == 0, f"Agent script failed on input {input_csv}. Stderr: {agent_proc.stderr}"
            assert os.path.isfile(agent_out), f"Agent script did not produce output file {agent_out}"

            with open(oracle_out, "r") as f_oracle, open(agent_out, "r") as f_agent:
                oracle_content = f_oracle.read()
                agent_content = f_agent.read()

            assert oracle_content == agent_content, (
                f"Mismatch on run {i + 1}!\n"
                f"Input CSV saved at: {input_csv}\n"
                f"Expected output:\n{oracle_content}\n"
                f"Got output:\n{agent_content}"
            )
        finally:
            for path in (input_csv, agent_out, oracle_out):
                if os.path.exists(path):
                    os.remove(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
