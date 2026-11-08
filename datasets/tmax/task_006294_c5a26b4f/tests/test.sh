#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile


def compute_expected(raw_data_dir):
    txt_files = [f for f in os.listdir(raw_data_dir) if f.endswith(".txt")]
    all_tokens = []
    for filename in txt_files:
        filepath = os.path.join(raw_data_dir, filename)
        with open(filepath, "r", encoding="utf-8") as f:
            all_tokens.extend(re.findall(r"[a-z]+", f.read().lower()))
    return f"Run1,{len(txt_files)},{len(all_tokens)},{len(set(all_tokens))}"


def test_go_program_exists():
    """Check that the Go program was created."""
    go_file = "/home/user/tokenize_dataset.go"
    assert os.path.isfile(go_file), f"Go program {go_file} is missing."


def test_experiments_csv_content():
    """Check that experiments.csv contains the correct computed metrics."""
    raw_data_dir = "/home/user/raw_data"
    assert os.path.isdir(raw_data_dir), f"Directory {raw_data_dir} is missing."

    expected_line = compute_expected(raw_data_dir)
    csv_file = "/home/user/experiments.csv"
    assert os.path.isfile(csv_file), f"File {csv_file} was not created."

    with open(csv_file, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines, f"File {csv_file} is empty."
    assert expected_line in lines, (
        f"Expected line '{expected_line}' not found in {csv_file}. Found: {lines}"
    )


def test_go_program_executes_and_tokenizes_controlled_data():
    """Run the submitted Go artifact and verify its behavior on controlled input."""
    go_file = "/home/user/tokenize_dataset.go"
    raw_data_dir = "/home/user/raw_data"
    csv_file = "/home/user/experiments.csv"

    backup_dir = tempfile.mkdtemp(prefix="tokenizer-verifier-")
    raw_backup = os.path.join(backup_dir, "raw_data")
    shutil.copytree(raw_data_dir, raw_backup)
    csv_existed = os.path.exists(csv_file)
    csv_backup = os.path.join(backup_dir, "experiments.csv")
    if csv_existed:
        shutil.copy2(csv_file, csv_backup)

    try:
        shutil.rmtree(raw_data_dir)
        os.makedirs(raw_data_dir)

        with open(os.path.join(raw_data_dir, "alpha.txt"), "w", encoding="utf-8") as f:
            f.write("Hello HELLO! can't abc123DEF; naïve Z.\n")
        with open(os.path.join(raw_data_dir, "beta.txt"), "w", encoding="utf-8") as f:
            f.write("WORLD...world _MiXeD_ q_q.\n")
        with open(os.path.join(raw_data_dir, "ignored.md"), "w", encoding="utf-8") as f:
            f.write("these words must not be counted")
        with open(os.path.join(raw_data_dir, "ignored.TXT"), "w", encoding="utf-8") as f:
            f.write("these words must also be ignored")

        expected_line = compute_expected(raw_data_dir)
        sentinel = "PreviousRun,99,99,99"
        with open(csv_file, "w", encoding="utf-8") as f:
            f.write(sentinel + "\n")

        result = subprocess.run(
            ["go", "run", go_file],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        assert result.returncode == 0, (
            "The submitted Go program failed when executed.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(csv_file), "The Go program did not create experiments.csv."

        with open(csv_file, "r", encoding="utf-8") as f:
            lines = [line.strip() for line in f if line.strip()]
        assert lines == [sentinel, expected_line], (
            "The Go program must append exactly one correctly computed line. "
            f"Expected {[sentinel, expected_line]}, found {lines}."
        )
    finally:
        if os.path.exists(raw_data_dir):
            shutil.rmtree(raw_data_dir)
        shutil.copytree(raw_backup, raw_data_dir)
        if os.path.exists(csv_file):
            os.remove(csv_file)
        if csv_existed:
            shutil.copy2(csv_backup, csv_file)
        shutil.rmtree(backup_dir)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
