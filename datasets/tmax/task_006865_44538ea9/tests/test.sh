#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import subprocess
import tempfile
import pytest

WORKDIR = "/home/user/mlops_exp"
CPP_PATH = os.path.join(WORKDIR, "pca_bayes.cpp")
BIN_PATH = os.path.join(WORKDIR, "pca_bayes")
DATA_PATH = os.path.join(WORKDIR, "data.csv")
METRICS_PATH = "/home/user/fixed_metrics.txt"


def compute_expected_accuracy(data_path):
    with open(data_path, "r") as f:
        lines = f.read().strip().split("\n")

    data = []
    for line in lines:
        if not line.strip():
            continue
        parts = line.split(",")
        data.append({
            "x": float(parts[0]),
            "y": float(parts[1]),
            "label": int(parts[2])
        })

    train_size = 80
    test_size = len(data) - train_size

    mean_x = sum(d["x"] for d in data[:train_size]) / train_size
    mean_y = sum(d["y"] for d in data[:train_size]) / train_size

    for d in data:
        centered_x = d["x"] - mean_x
        centered_y = d["y"] - mean_y
        d["projected"] = (centered_x + centered_y) / 2.0

    mean_class0 = 0.0
    mean_class1 = 0.0
    count0 = 0
    count1 = 0
    for d in data[:train_size]:
        if d["label"] == 0:
            mean_class0 += d["projected"]
            count0 += 1
        else:
            mean_class1 += d["projected"]
            count1 += 1

    if count0 > 0:
        mean_class0 /= count0
    if count1 > 0:
        mean_class1 /= count1

    correct = 0
    for d in data[train_size:]:
        dist0 = abs(d["projected"] - mean_class0)
        dist1 = abs(d["projected"] - mean_class1)
        pred = 0 if dist0 < dist1 else 1
        if pred == d["label"]:
            correct += 1

    return correct / test_size


def parse_single_number(output, description):
    text = output.decode("utf-8") if isinstance(output, bytes) else output
    assert re.fullmatch(
        r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\s*",
        text,
    ), f"{description} did not contain exactly one floating-point number: {text!r}"
    return float(text.strip())


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(65536), b""):
            digest.update(block)
    return digest.digest()


def test_fixed_metrics_file():
    assert os.path.isfile(METRICS_PATH), f"File {METRICS_PATH} does not exist."
    assert os.path.isfile(DATA_PATH), f"File {DATA_PATH} does not exist."

    expected_acc = compute_expected_accuracy(DATA_PATH)

    with open(METRICS_PATH, "r") as f:
        content = f.read().strip()

    try:
        actual_acc = float(content)
    except ValueError:
        pytest.fail(f"Could not parse '{content}' as a float in {METRICS_PATH}.")

    assert abs(actual_acc - expected_acc) < 1e-6, (
        f"Expected accuracy {expected_acc}, but got {actual_acc} in {METRICS_PATH}."
    )


def test_cpp_code_fixed():
    assert os.path.isfile(CPP_PATH), f"File {CPP_PATH} does not exist."

    with open(CPP_PATH, "r") as f:
        content = f.read()

    # Preserve the original denominator assertions.
    assert "mean_x /= train_size;" in content or "mean_x /= (double)train_size;" in content or "mean_x /= (float)train_size;" in content or "mean_x = mean_x / train_size;" in content.replace(" ", ""), "The C++ code does not seem to divide by train_size for mean_x."
    assert "mean_y /= train_size;" in content or "mean_y /= (double)train_size;" in content or "mean_y /= (float)train_size;" in content or "mean_y = mean_y / train_size;" in content.replace(" ", ""), "The C++ code does not seem to divide by train_size for mean_y."
    assert "mean_x /= total_size;" not in content, "The C++ code still divides by total_size for mean_x."
    assert "mean_y /= total_size;" not in content, "The C++ code still divides by total_size for mean_y."

    # Validate the actual mean-accumulation block, rather than accepting an
    # unrelated occurrence of train_size elsewhere in the program.
    no_comments = re.sub(r"/\*.*?\*/", "", content, flags=re.S)
    no_comments = re.sub(r"//[^\n]*", "", no_comments)
    mean_block = re.compile(
        r"double\s+mean_x\s*=\s*0\s*;\s*"
        r"double\s+mean_y\s*=\s*0\s*;\s*"
        r"for\s*\(\s*int\s+i\s*=\s*0\s*;\s*i\s*<\s*train_size\s*;\s*\+\+i\s*\)\s*\{\s*"
        r"mean_x\s*\+=\s*data\s*\[\s*i\s*\]\s*\.\s*x\s*;\s*"
        r"mean_y\s*\+=\s*data\s*\[\s*i\s*\]\s*\.\s*y\s*;\s*"
        r"\}\s*"
        r"mean_x\s*/=\s*(?:\(\s*(?:double|float)\s*\)\s*)?train_size\s*;\s*"
        r"mean_y\s*/=\s*(?:\(\s*(?:double|float)\s*\)\s*)?train_size\s*;",
        flags=re.S,
    )
    assert mean_block.search(no_comments), (
        "The mean accumulation loop and its denominators must use train_size."
    )


def test_cpp_binary_exists_and_matches_source():
    assert os.path.isfile(BIN_PATH), f"Compiled binary {BIN_PATH} does not exist."
    assert os.access(BIN_PATH, os.X_OK), f"File {BIN_PATH} is not executable."

    expected_acc = compute_expected_accuracy(DATA_PATH)

    with tempfile.TemporaryDirectory() as tempdir:
        rebuilt = os.path.join(tempdir, "pca_bayes")
        compile_result = subprocess.run(
            ["g++", "-O3", "pca_bayes.cpp", "-o", rebuilt],
            cwd=WORKDIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "The submitted C++ source does not compile with the required command:\n"
            + compile_result.stderr.decode("utf-8", errors="replace")
        )

        # This ensures the required executable is the artifact produced from
        # the submitted source, rather than an arbitrary executable file.
        assert sha256_file(BIN_PATH) == sha256_file(rebuilt), (
            "The submitted pca_bayes executable does not match a fresh "
            "g++ -O3 build of pca_bayes.cpp."
        )

        rebuilt_run = subprocess.run(
            [rebuilt], cwd=WORKDIR, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, timeout=10
        )
        assert rebuilt_run.returncode == 0, (
            "The freshly compiled program failed: "
            + rebuilt_run.stderr.decode("utf-8", errors="replace")
        )
        rebuilt_acc = parse_single_number(rebuilt_run.stdout, "Compiled program output")
        assert abs(rebuilt_acc - expected_acc) < 1e-6, (
            f"Compiled source printed {rebuilt_acc}; expected {expected_acc}."
        )

    submitted_run = subprocess.run(
        [BIN_PATH], cwd=WORKDIR, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    )
    assert submitted_run.returncode == 0, (
        "The submitted executable failed: "
        + submitted_run.stderr.decode("utf-8", errors="replace")
    )
    submitted_acc = parse_single_number(submitted_run.stdout, "Submitted executable output")
    assert abs(submitted_acc - expected_acc) < 1e-6, (
        f"Submitted executable printed {submitted_acc}; expected {expected_acc}."
    )

    with open(METRICS_PATH, "r") as f:
        metric_acc = parse_single_number(f.read(), METRICS_PATH)
    assert abs(metric_acc - submitted_acc) < 1e-12, (
        "fixed_metrics.txt does not contain the output of the submitted executable."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
