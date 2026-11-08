#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import math
import os
import subprocess

import pytest

SCRIPT = "/home/user/benchmark.py"
CSV_PATH = "/home/user/data/reviews.csv"
METRICS = "/home/user/results/metrics.json"
PNG = "/home/user/results/token_dist.png"


def run_benchmark():
    for path in (METRICS, PNG):
        if os.path.exists(path):
            os.remove(path)
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"benchmark.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(SCRIPT), f"The script {SCRIPT} does not exist."
    run_benchmark()


def test_benchmark_script_exists():
    """Verify that the benchmark script was created."""
    assert os.path.isfile(SCRIPT), f"The script {SCRIPT} does not exist."


def test_script_uses_required_pipeline_components():
    """Inspect the executable script for the required libraries and timing region."""
    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    assert source.strip(), "benchmark.py is empty."

    tree = ast.parse(source, filename=SCRIPT)
    imported = set()
    calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module.split(".")[0])
        elif isinstance(node, ast.Call):
            calls.append(node)

    assert "pandas" in imported, "benchmark.py must import pandas."
    assert "tiktoken" in imported, "benchmark.py must import tiktoken."
    assert "matplotlib" in imported, "benchmark.py must import matplotlib."

    def dotted_name(node):
        if isinstance(node, ast.Name):
            return node.id
        if isinstance(node, ast.Attribute):
            prefix = dotted_name(node.value)
            return f"{prefix}.{node.attr}" if prefix else node.attr
        return ""

    named_calls = [(dotted_name(call.func), call) for call in calls]
    assert any(name.endswith("get_encoding") and call.args and
               isinstance(call.args[0], ast.Constant) and
               call.args[0].value == "cl100k_base"
               for name, call in named_calls), "The cl100k_base encoding must be selected."
    assert any(name.endswith("read_csv") for name, _ in named_calls), "The CSV must be read with pandas."
    assert any(name.endswith("hist") for name, _ in named_calls), "A matplotlib histogram must be generated."
    assert any(name.endswith("savefig") for name, _ in named_calls), "The plot must be saved with savefig()."

    backend_calls = [call for name, call in named_calls if name.endswith(".use") or name == "use"]
    assert any(
        (call.args and isinstance(call.args[0], ast.Constant) and
         str(call.args[0].value).lower() == "agg") or
        any(kw.arg == "backend" and isinstance(kw.value, ast.Constant) and
            str(kw.value.value).lower() == "agg" for kw in call.keywords)
        for call in backend_calls
    ), "benchmark.py must configure matplotlib's Agg headless backend."

    timer_lines = [call.lineno for name, call in named_calls if name.endswith("perf_counter")]
    encode_lines = [call.lineno for name, call in named_calls if name.endswith("encode")]
    assert len(timer_lines) >= 2, "time.perf_counter() must be called before and after tokenization."
    assert encode_lines, "Reviews must be tokenized by calling the encoding's encode method."
    assert min(timer_lines) <= min(encode_lines) and max(timer_lines) >= max(encode_lines), \
        "Tokenization must occur between the perf_counter() calls."


def test_metrics_json_exists_and_valid():
    """Verify that metrics.json exists, is valid JSON, and contains correct values."""
    assert os.path.isfile(METRICS), f"The file {METRICS} does not exist."
    with open(METRICS, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {METRICS} does not contain valid JSON.")

    assert "total_tokens" in metrics, "Missing 'total_tokens' in metrics.json"
    assert "time_seconds" in metrics, "Missing 'time_seconds' in metrics.json"
    assert isinstance(metrics["total_tokens"], int), "'total_tokens' must be an integer."
    assert metrics["total_tokens"] == 93, f"Expected 93 total tokens, got {metrics['total_tokens']}."
    assert isinstance(metrics["time_seconds"], (int, float)), "'time_seconds' must be a number."
    assert metrics["time_seconds"] > 0, "'time_seconds' must be a positive float."


def test_token_dist_png_exists_and_valid():
    """Verify that token_dist.png exists and is a valid, nonblank PNG image."""
    assert os.path.isfile(PNG), f"The file {PNG} does not exist."
    with open(PNG, "rb") as f:
        header = f.read(8)
    assert header == b"\x89PNG\r\n\x1a\n", f"The file {PNG} is not a valid PNG image."

    import matplotlib.image as mpimg
    image = mpimg.imread(PNG)
    assert image.ndim in (2, 3) and image.shape[0] >= 100 and image.shape[1] >= 100, \
        "token_dist.png must be a rendered plot, not merely a PNG header."
    assert float(image.std()) > 0.001, "token_dist.png appears blank."


def test_pipeline_on_derived_dataset():
    """Run the submitted pipeline on new reviews and derive the expected answer independently."""
    import tiktoken

    reviews = [
        "Short.",
        "Numbers 12345 and punctuation: alpha, beta; gamma!",
        "Unicode café naïve — 東京 🚀",
        "A deliberately longer review " + "with repeated words " * 17,
    ]
    expected = sum(len(tiktoken.get_encoding("cl100k_base").encode(text)) for text in reviews)

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()
    try:
        with open(CSV_PATH, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=["review_text"])
            writer.writeheader()
            for text in reviews:
                writer.writerow({"review_text": text})

        run_benchmark()
        with open(METRICS, "r", encoding="utf-8") as f:
            metrics = json.load(f)
        assert type(metrics.get("total_tokens")) is int
        assert metrics["total_tokens"] == expected, (
            f"For the verifier dataset, expected {expected} tokens but got "
            f"{metrics.get('total_tokens')}."
        )
        assert isinstance(metrics.get("time_seconds"), (int, float))
        assert not isinstance(metrics["time_seconds"], bool)
        assert math.isfinite(metrics["time_seconds"]) and metrics["time_seconds"] > 0

        import matplotlib.image as mpimg
        image = mpimg.imread(PNG)
        assert image.shape[0] >= 100 and image.shape[1] >= 100
        assert float(image.std()) > 0.001, "The generated histogram appears blank."
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        run_benchmark()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
