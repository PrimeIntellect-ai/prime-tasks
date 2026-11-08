#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat
import secrets
import string
import subprocess
import tempfile
import pytest

PROJECT = "/home/user/etl_tool"
PIPELINE = "/home/user/pipeline.sh"
RAW = "/home/user/data/raw.txt"
OUTPUTS = [
    "/home/user/data/embeddings.csv",
    "/home/user/data/predictions.txt",
    "/home/user/data/closest.txt",
]

def compute_vcd(text):
    v = sum(1 for char in text if char.lower() in 'aeiou')
    c = sum(1 for char in text if char.isalpha() and char.lower() not in 'aeiou')
    d = sum(1 for char in text if char.isdigit())
    return v, c, d

def expected_outputs(lines):
    csv_lines = ["id,v,c,d"]
    prediction_lines = []
    best_id = -1
    min_dist = float('inf')
    for i, line in enumerate(lines):
        v, c, d = compute_vcd(line)
        csv_lines.append(f"{i},{v},{c},{d}")
        score = (v * 1.5) + (c * -0.5) + (d * 2.0)
        prediction_lines.append(f"{i},{score:.1f}")
        dist = (v - 5) ** 2 + (c - 10) ** 2 + (d - 3) ** 2
        if dist < min_dist:
            min_dist = dist
            best_id = i
    return csv_lines, prediction_lines, str(best_id)

def remove_outputs():
    for path in OUTPUTS:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

def run_pipeline():
    subprocess.run([PIPELINE], cwd="/tmp", check=True, timeout=180)

def assert_pipeline_outputs(lines):
    expected_csv, expected_predictions, expected_closest = expected_outputs(lines)
    assert os.path.isfile(OUTPUTS[0]), "Pipeline did not create embeddings.csv"
    assert os.path.isfile(OUTPUTS[1]), "Pipeline did not create predictions.txt"
    assert os.path.isfile(OUTPUTS[2]), "Pipeline did not create closest.txt"
    assert open(OUTPUTS[0], encoding="utf-8").read().splitlines() == expected_csv
    assert open(OUTPUTS[1], encoding="utf-8").read().splitlines() == expected_predictions
    assert open(OUTPUTS[2], encoding="utf-8").read().strip() == expected_closest

def cargo_run(*args):
    return subprocess.run(
        ["cargo", "run", "--quiet", "--release", "--", *map(str, args)],
        cwd=PROJECT,
        check=True,
        text=True,
        capture_output=True,
        timeout=180,
    )

def test_pipeline_script_exists_and_executable():
    script_path = "/home/user/pipeline.sh"
    assert os.path.isfile(script_path), f"Pipeline script {script_path} does not exist."
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Pipeline script {script_path} is not executable."

def test_rust_project_builds_and_subcommands_work_on_unseen_input():
    assert os.path.isdir(PROJECT), f"Rust project {PROJECT} does not exist."
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Cargo.toml is missing."
    assert os.path.isfile(os.path.join(PROJECT, "src", "main.rs")), "src/main.rs is missing."
    subprocess.run(["cargo", "build", "--release"], cwd=PROJECT, check=True, timeout=180)

    token = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(31))
    lines = ["b", "a", "zzzz", token, "AEIOU xyz 907", ""]
    with tempfile.TemporaryDirectory() as td:
        input_txt = os.path.join(td, "input.txt")
        output_csv = os.path.join(td, "embeddings.csv")
        output_predictions = os.path.join(td, "predictions.txt")
        with open(input_txt, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")

        cargo_run("embed", input_txt, output_csv)
        expected_csv, expected_predictions, _ = expected_outputs(lines)
        assert open(output_csv, encoding="utf-8").read().splitlines() == expected_csv

        cargo_run("predict", output_csv, output_predictions)
        assert open(output_predictions, encoding="utf-8").read().splitlines() == expected_predictions

        tied = cargo_run("retrieve", output_csv, "0", "0", "0")
        assert tied.stdout.strip() == "0", "retrieve must choose the lowest id on a tie"
        exact = cargo_run("retrieve", output_csv, "5", "3", "3")
        vectors = [compute_vcd(line) for line in lines]
        distances = [sum((x - y) ** 2 for x, y in zip(vec, (5, 3, 3))) for vec in vectors]
        assert exact.stdout.strip() == str(min(range(len(lines)), key=lambda i: (distances[i], i)))

def test_pipeline_executes_on_unseen_data_and_regenerates_outputs():
    original_raw = open(RAW, "rb").read()
    token = ''.join(secrets.choice(string.ascii_letters + string.digits) for _ in range(47))
    probe_lines = [token, "Only vowels: AEIOUaeiou", "BCDFG 24680", "", "query 555 abc"]
    try:
        with open(RAW, "w", encoding="utf-8") as f:
            f.write("\n".join(probe_lines) + "\n")
        remove_outputs()
        run_pipeline()
        assert_pipeline_outputs(probe_lines)
    finally:
        with open(RAW, "wb") as f:
            f.write(original_raw)
        remove_outputs()
        run_pipeline()

def test_embeddings_csv():
    raw_path = "/home/user/data/raw.txt"
    csv_path = "/home/user/data/embeddings.csv"

    assert os.path.isfile(raw_path), f"Input file {raw_path} is missing."
    assert os.path.isfile(csv_path), f"Output file {csv_path} is missing."

    with open(raw_path, "r") as f:
        lines = f.read().splitlines()

    expected_csv_lines = ["id,v,c,d"]
    for i, line in enumerate(lines):
        v, c, d = compute_vcd(line)
        expected_csv_lines.append(f"{i},{v},{c},{d}")

    with open(csv_path, "r") as f:
        actual_csv_lines = [line.strip() for line in f.read().splitlines() if line.strip()]

    assert actual_csv_lines == expected_csv_lines, "The embeddings.csv does not match the expected output."

def test_predictions_txt():
    raw_path = "/home/user/data/raw.txt"
    txt_path = "/home/user/data/predictions.txt"

    assert os.path.isfile(raw_path), f"Input file {raw_path} is missing."
    assert os.path.isfile(txt_path), f"Output file {txt_path} is missing."

    with open(raw_path, "r") as f:
        lines = f.read().splitlines()

    expected_txt_lines = []
    for i, line in enumerate(lines):
        v, c, d = compute_vcd(line)
        score = (v * 1.5) + (c * -0.5) + (d * 2.0)
        expected_txt_lines.append(f"{i},{score:.1f}")

    with open(txt_path, "r") as f:
        actual_txt_lines = [line.strip() for line in f.read().splitlines() if line.strip()]

    assert actual_txt_lines == expected_txt_lines, "The predictions.txt does not match the expected output."

def test_closest_txt():
    raw_path = "/home/user/data/raw.txt"
    txt_path = "/home/user/data/closest.txt"

    assert os.path.isfile(raw_path), f"Input file {raw_path} is missing."
    assert os.path.isfile(txt_path), f"Output file {txt_path} is missing."

    with open(raw_path, "r") as f:
        lines = f.read().splitlines()

    min_dist = float('inf')
    best_id = -1

    for i, line in enumerate(lines):
        v, c, d = compute_vcd(line)
        dist = (v - 5)**2 + (c - 10)**2 + (d - 3)**2
        if dist < min_dist:
            min_dist = dist
            best_id = i

    with open(txt_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == str(best_id), f"The closest.txt content should be '{best_id}', but got '{actual_content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
