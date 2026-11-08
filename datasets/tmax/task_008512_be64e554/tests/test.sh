#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tempfile

PROJECT = "/home/user/data_gen"
MAIN_RS = os.path.join(PROJECT, "src/main.rs")
BINARY = os.path.join(PROJECT, "target/release/data_gen")
INPUT = "/home/user/input_data.csv"
OUTPUT = "/home/user/output_features.csv"
REFERENCE = "/home/user/reference_features.csv"


def test_rust_code_modified():
    assert os.path.isfile(MAIN_RS), f"{MAIN_RS} does not exist"
    with open(MAIN_RS, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "Mutex::new" not in content, "main.rs still contains Mutex::new usage which causes non-determinism"
    assert "par_iter" not in content, "main.rs still contains par_iter usage for the reduction"
    assert "iter()" in content, "main.rs should use sequential iter()"
    assert "sum()" in content or "sum::<" in content, "main.rs should use sum() for reduction"

    # Ensure the required iterator operations occur in code rather than only in comments or strings.
    code = re.sub(r"/\*.*?\*/|//[^\n]*|\"(?:\\.|[^\"\\])*\"", " ", content, flags=re.S)
    assert re.search(r"\.iter\s*\(\s*\)\s*\.map\s*\(", code), \
        "main.rs must use a sequential iter().map(...) chain"
    assert re.search(r"\.sum\s*::\s*<\s*f64\s*>\s*\(\s*\)", code), \
        "main.rs must use sum::<f64>() for the reduction"


def test_binary_compiled():
    assert os.path.isfile(BINARY), f"Compiled binary not found at {BINARY}. Did you run 'cargo build --release'?"
    assert os.access(BINARY, os.X_OK), f"Binary at {BINARY} is not executable."


def test_output_features_matches_reference():
    assert os.path.isfile(OUTPUT), f"{OUTPUT} does not exist. Did you run the compiled binary?"
    assert os.path.isfile(REFERENCE), f"{REFERENCE} is missing."

    with open(OUTPUT, "r") as f:
        output_content = f.read().strip()
    with open(REFERENCE, "r") as f:
        reference_content = f.read().strip()

    assert output_content == reference_content, \
        f"Output features ({output_content}) do not exactly match reference features ({reference_content})."


def test_regression_result_file():
    result_path = "/home/user/regression_result.txt"
    assert os.path.isfile(result_path), f"{result_path} does not exist."
    assert os.path.isfile(REFERENCE), f"{REFERENCE} is missing."

    with open(REFERENCE, "r") as f:
        reference_content = f.read().strip()
    with open(result_path, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) >= 2, f"{result_path} must contain at least 2 lines."
    assert lines[0] == "PASS", f"First line of {result_path} must be exactly 'PASS', got '{lines[0]}'."
    assert lines[1] == reference_content, \
        f"Second line of {result_path} must exactly match the reference output '{reference_content}', got '{lines[1]}'."


def test_rebuild_and_execute_submission_on_derived_cases():
    oracle_src = r'''
use std::env;
use std::fs::File;
use std::io::{BufRead, BufReader};

fn main() {
    let file = File::open(env::args().nth(1).unwrap()).unwrap();
    let reader = BufReader::new(file);
    let mut data: Vec<f64> = Vec::new();
    for line in reader.lines() {
        if let Ok(val) = line.unwrap().parse::<f64>() {
            data.push(val);
        }
    }
    let final_val: f64 = data.iter().map(|&val| val.sin()).sum::<f64>();
    println!("{:.10}", final_val);
}
'''

    with tempfile.TemporaryDirectory() as td:
        oracle_rs = os.path.join(td, "oracle.rs")
        oracle_bin = os.path.join(td, "oracle")
        with open(oracle_rs, "w") as f:
            f.write(oracle_src)
        subprocess.run(["rustc", "-O", oracle_rs, "-o", oracle_bin], check=True, timeout=120)

        original_input = open(INPUT, "rb").read()
        original_output = open(OUTPUT, "rb").read()

        def expected(path):
            return subprocess.run([oracle_bin, path], check=True, stdout=subprocess.PIPE,
                                  timeout=30).stdout

        try:
            # Force the checked artifact to be rebuilt from the submitted source.
            subprocess.run(["cargo", "clean"], cwd=PROJECT, check=True, timeout=120)
            subprocess.run(["cargo", "build", "--release"], cwd=PROJECT, check=True, timeout=300)
            assert os.path.isfile(BINARY), "cargo build --release did not produce the required binary"
            assert os.access(BINARY, os.X_OK), "rebuilt data_gen artifact is not executable"

            # Validate the shipped reference independently and execute the rebuilt binary on it.
            original_expected = expected(INPUT)
            assert open(REFERENCE, "rb").read() == original_expected, \
                "reference_features.csv does not contain the sequential reduction result"
            if os.path.exists(OUTPUT):
                os.remove(OUTPUT)
            subprocess.run([BINARY], cwd=PROJECT, check=True, timeout=120)
            assert open(OUTPUT, "rb").read() == original_expected, \
                "rebuilt binary does not produce the sequential result for the provided input"

            rng = secrets.SystemRandom()
            random_values = [format(rng.uniform(-10000.0, 10000.0), ".17g") for _ in range(8192)]
            sensitive_values = []
            for _ in range(20000):
                sensitive_values.extend(["1.5707963267948966", "0.000000000001", "-1.5707963267948966"])

            for values in (random_values, sensitive_values):
                with open(INPUT, "w") as f:
                    f.write("\n".join(values) + "\n")
                wanted = expected(INPUT)
                for _ in range(2):
                    if os.path.exists(OUTPUT):
                        os.remove(OUTPUT)
                    subprocess.run([BINARY], cwd=PROJECT, check=True, timeout=120)
                    assert os.path.isfile(OUTPUT), "executed binary did not create output_features.csv"
                    assert open(OUTPUT, "rb").read() == wanted, \
                        "executed binary did not perform the required deterministic sequential sin reduction"
        finally:
            with open(INPUT, "wb") as f:
                f.write(original_input)
            with open(OUTPUT, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
