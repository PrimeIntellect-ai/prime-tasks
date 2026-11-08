#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import re
import subprocess
from pathlib import Path

import pytest

HOME = Path("/home/user")


def test_embed_py_exists():
    """Verify that embed.py exists."""
    assert os.path.isfile("/home/user/embed.py"), "embed.py was not found at /home/user/embed.py"


def test_retrieve_r_exists():
    """Verify that retrieve.R exists."""
    assert os.path.isfile("/home/user/retrieve.R"), "retrieve.R was not found at /home/user/retrieve.R"


def test_run_pipeline_sh_exists_and_executable():
    """Verify that run_pipeline.sh exists and is executable."""
    path = "/home/user/run_pipeline.sh"
    assert os.path.isfile(path), f"run_pipeline.sh was not found at {path}"
    assert os.access(path, os.X_OK), f"{path} is not executable"


def test_top_concept_txt_exists_and_correct():
    """Verify that top_concept.txt exists and contains the correct ID."""
    path = "/home/user/top_concept.txt"
    assert os.path.isfile(path), f"{path} was not found. Did the pipeline run successfully?"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "3", f"Expected top_concept.txt to contain '3', but got '{content}'"


def test_scripts_describe_required_pipeline():
    embed = (HOME / "embed.py").read_text(errors="replace")
    pipeline = (HOME / "run_pipeline.sh").read_text(errors="replace")

    assert "sentence_transformers" in embed or "sentence-transformers" in embed, \
        "embed.py does not use the sentence-transformers library"
    assert "all-MiniLM-L6-v2" in embed, \
        "embed.py does not load the required all-MiniLM-L6-v2 model"
    assert re.search(r"\.encode\s*\(", embed), \
        "embed.py does not call the model's encode method"
    assert "embed.py" in pipeline, "run_pipeline.sh does not invoke embed.py"
    assert "retrieve.R" in pipeline, "run_pipeline.sh does not invoke retrieve.R"

    lower_pipeline = pipeline.lower()
    installer = re.search(r"\b(pip3?|uv)\b", lower_pipeline) and "install" in lower_pipeline
    dependency_spec = "sentence-transformers" in lower_pipeline or re.search(r"(?:^|\s)-r\s+\S+", lower_pipeline)
    assert installer and dependency_spec, \
        "run_pipeline.sh does not install the required Python dependencies"


def _read_numeric_csv(path):
    with open(path, newline="") as f:
        rows = list(csv.reader(f))
    assert rows, f"{path} is empty"
    width = len(rows[0])
    assert width > 1, f"{path} does not contain embedding vectors"
    assert all(len(row) == width for row in rows), f"{path} has inconsistent row widths"
    try:
        values = [[float(value) for value in row] for row in rows]
    except ValueError as exc:
        pytest.fail(f"{path} contains a header or non-numeric data: {exc}")
    assert all(math.isfinite(value) for row in values for value in row), \
        f"{path} contains non-finite values"
    return values


def test_pipeline_executes_and_produces_real_embeddings():
    # Remove all products so pre-created files cannot satisfy this test.
    for name in ("embeddings.csv", "query.csv", "top_concept.txt"):
        path = HOME / name
        if path.exists():
            path.unlink()

    result = subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user", str(HOME / "run_pipeline.sh")],
        cwd=str(HOME), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        timeout=900,
    )
    assert result.returncode == 0, f"run_pipeline.sh failed:\n{result.stdout}"

    embeddings = _read_numeric_csv(HOME / "embeddings.csv")
    query = _read_numeric_csv(HOME / "query.csv")
    assert len(embeddings) == 5, "embeddings.csv must have one row per input description"
    assert len(query) == 1, "query.csv must contain exactly one embedding"
    assert len(embeddings[0]) == len(query[0]), "concept and query dimensions differ"
    assert len(embeddings[0]) == 384, \
        "all-MiniLM-L6-v2 should produce 384-dimensional embeddings"
    assert (HOME / "top_concept.txt").read_text().strip() == "3"


def test_retrieve_r_computes_cosine_similarity():
    paths = [HOME / name for name in ("math_concepts.csv", "embeddings.csv", "query.csv", "top_concept.txt")]
    saved = {path: path.read_bytes() for path in paths}

    # These candidates make cosine similarity, raw dot product, and Euclidean
    # distance choose different rows. Derive the expected ID independently.
    vectors = [[100.0, 1.0], [1.0, 0.2], [200.0, 200.0]]
    query = [1.0, 0.0]
    ids = [907, 411, 263]
    similarities = [
        sum(a * b for a, b in zip(vector, query)) /
        (math.sqrt(sum(a * a for a in vector)) * math.sqrt(sum(b * b for b in query)))
        for vector in vectors
    ]
    expected = str(ids[max(range(len(ids)), key=similarities.__getitem__)])

    try:
        (HOME / "math_concepts.csv").write_text(
            "ID,Description\n907,first synthetic concept\n411,second synthetic concept\n263,third synthetic concept\n"
        )
        (HOME / "embeddings.csv").write_text("100,1\n1,0.2\n200,200\n")
        (HOME / "query.csv").write_text("1,0\n")
        (HOME / "top_concept.txt").unlink(missing_ok=True)

        result = subprocess.run(
            ["runuser", "-u", "user", "--", "Rscript", str(HOME / "retrieve.R")],
            cwd=str(HOME), text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=120,
        )
        assert result.returncode == 0, f"retrieve.R failed on synthetic vectors:\n{result.stdout}"
        assert (HOME / "top_concept.txt").is_file(), "retrieve.R did not create top_concept.txt"
        actual = (HOME / "top_concept.txt").read_text().strip()
        assert actual == expected, \
            f"retrieve.R did not select the independently computed cosine-similarity winner: {actual}"
    finally:
        for path, data in saved.items():
            path.write_bytes(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
