#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import math
import struct
import re
import subprocess
import pytest

SCRIPT_PATH = "/home/user/run_pipeline.sh"
OUTPUT_PATH = "/home/user/output/top_pairs.csv"
REVIEWS_PATH = "/home/user/data/reviews.csv"


def read_npy(filepath):
    """Minimal pure-Python NPY file reader for 1D/2D float32 arrays."""
    with open(filepath, 'rb') as f:
        magic = f.read(6)
        if magic != b'\x93NUMPY':
            raise ValueError(f"Not a valid .npy file: {filepath}")
        major, minor = struct.unpack('<BB', f.read(2))
        if major == 1:
            header_len = struct.unpack('<H', f.read(2))[0]
        else:
            header_len = struct.unpack('<I', f.read(4))[0]
        header_str = f.read(header_len).decode('ascii')

        header_dict = eval(header_str.strip())
        shape = header_dict['shape']
        descr = header_dict['descr']

        if descr != '<f4':
            raise ValueError(f"Unsupported dtype: {descr}")

        data = f.read()
        num_elements = 1
        for dim in shape:
            num_elements *= dim

        values = struct.unpack('<' + 'f' * num_elements, data)

        if len(shape) == 1:
            return list(values)
        elif len(shape) == 2:
            res = []
            for i in range(shape[0]):
                res.append(list(values[i*shape[1]:(i+1)*shape[1]]))
            return res
        else:
            raise ValueError("Only 1D and 2D arrays are supported")


def compute_ground_truth():
    """Derive the expected output directly from the current data and model files."""
    with open("/home/user/model/vocab.json", "r") as f:
        vocab = json.load(f)

    embeddings = read_npy("/home/user/model/embeddings.npy")
    linear_w = read_npy("/home/user/model/linear_w.npy")
    linear_b = read_npy("/home/user/model/linear_b.npy")

    reviews = []
    with open(REVIEWS_PATH, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            reviews.append(row)

    review_embeddings = {}
    for review in reviews:
        text = review["text"].lower()
        text = re.sub(r'[^\w\s]', '', text)
        tokens = text.split()
        indices = [vocab.get(token, 0) for token in tokens]

        if not indices:
            pooled = [0.0] * 32
        else:
            pooled = [0.0] * 32
            for idx in indices:
                emb = embeddings[idx]
                for i in range(32):
                    pooled[i] += emb[i]
            for i in range(32):
                pooled[i] /= len(indices)

        proj = [0.0] * 16
        for i in range(16):
            val = 0.0
            for j in range(32):
                val += linear_w[i][j] * pooled[j]
            proj[i] = val + linear_b[i]

        review_embeddings[review["id"]] = proj

    ids = list(review_embeddings.keys())
    pairs = []
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            id1, id2 = ids[i], ids[j]
            if id1 > id2:
                id1, id2 = id2, id1

            vec1 = review_embeddings[id1]
            vec2 = review_embeddings[id2]
            dot = sum(vec1[k] * vec2[k] for k in range(16))
            norm1 = math.sqrt(sum(vec1[k]**2 for k in range(16)))
            norm2 = math.sqrt(sum(vec2[k]**2 for k in range(16)))

            if norm1 == 0 or norm2 == 0:
                sim = 0.0
            else:
                sim = dot / (norm1 * norm2)

            pairs.append((id1, id2, round(sim, 4)))

    pairs.sort(key=lambda x: (-x[2], x[0], x[1]))
    return pairs[:3]


def run_pipeline_from_clean_output():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run(
        ["bash", SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"run_pipeline.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), (
        "Running run_pipeline.sh from a clean output state did not create "
        "/home/user/output/top_pairs.csv."
    )


def assert_output_file_content():
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["id1", "id2", "similarity"], f"Incorrect CSV header. Expected ['id1', 'id2', 'similarity'], got {header}"
        rows = list(reader)

    assert len(rows) == 3, f"Expected exactly 3 rows of data, got {len(rows)}."
    expected_pairs = compute_ground_truth()

    for i, (row, expected) in enumerate(zip(rows, expected_pairs)):
        assert len(row) == 3, f"Row {i+1} does not have 3 columns."
        id1, id2, sim_str = row
        assert id1 == expected[0], f"Row {i+1} id1 mismatch: expected {expected[0]}, got {id1}"
        assert id2 == expected[1], f"Row {i+1} id2 mismatch: expected {expected[1]}, got {id2}"

        try:
            sim = float(sim_str)
        except ValueError:
            pytest.fail(f"Row {i+1} similarity is not a valid float: {sim_str}")

        assert math.isclose(sim, expected[2], abs_tol=1e-4), f"Row {i+1} similarity mismatch: expected {expected[2]}, got {sim}"


def test_run_pipeline_script_exists():
    """Test that the run_pipeline.sh script exists."""
    assert os.path.isfile(SCRIPT_PATH), "The script /home/user/run_pipeline.sh is missing."


def test_run_pipeline_script_executes_workflow():
    """The submitted script must recreate the output when no output is present."""
    run_pipeline_from_clean_output()


def test_output_file_exists():
    """Test that the output CSV file was created."""
    assert os.path.isfile(OUTPUT_PATH), "The output file /home/user/output/top_pairs.csv is missing."


def test_output_file_content():
    """Test that the output CSV file contains the correct top 3 pairs."""
    assert_output_file_content()


def test_pipeline_uses_current_review_data():
    """Rerun on changed valid input so a fixed-output script cannot pass."""
    with open(REVIEWS_PATH, "rb") as f:
        original_reviews = f.read()

    try:
        with open(REVIEWS_PATH, "r", encoding="utf-8", newline="") as f:
            rows = list(csv.DictReader(f))

        original_texts = [row["text"] for row in rows]
        for i, row in enumerate(rows):
            row["id"] = "M_" + row["id"]
            row["text"] = original_texts[(i + 3) % len(original_texts)]

        with open(REVIEWS_PATH, "w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["id", "text"])
            writer.writeheader()
            writer.writerows(rows)

        run_pipeline_from_clean_output()
        assert_output_file_content()
    finally:
        with open(REVIEWS_PATH, "wb") as f:
            f.write(original_reviews)
        run_pipeline_from_clean_output()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
