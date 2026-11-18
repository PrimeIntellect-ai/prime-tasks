#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import csv
import math
import random
import string
import subprocess
import uuid
import pytest
import numpy as np


def test_tiny_embedder_fixed():
    """Verify that the bug is fixed in tiny-embedder core.py."""
    core_py = "/app/tiny-embedder/tiny_embedder/core.py"
    assert os.path.isfile(core_py), f"File missing: {core_py}"
    with open(core_py, "r") as f:
        content = f.read()

    assert "axis=1" in content, "The bug (axis=0) was not fixed to axis=1 in core.py"
    assert "axis=0" not in content, "The bug (axis=0) is still present in core.py"


def test_tiny_embedder_installed():
    """Verify that the tiny-embedder package is installed and works correctly."""
    try:
        import tiny_embedder
    except ImportError:
        pytest.fail("tiny_embedder is not installed in the environment.")

    embedder = tiny_embedder.TinyEmbedder()
    vecs = embedder.embed(["hello world", "test"])
    norms = np.linalg.norm(vecs, axis=1)
    np.testing.assert_allclose(norms, [1.0, 1.0], err_msg="Embeddings are not L2-normalized correctly. The fix might be incorrect.")


def test_script_exists():
    """Verify that the filter_csv.py script exists."""
    script_path = "/home/user/filter_csv.py"
    assert os.path.isfile(script_path), f"Script missing: {script_path}"


def test_adversarial_corpus_filtering(tmp_path):
    """Run the agent's script on clean and evil corpora and verify the output."""
    script_path = "/home/user/filter_csv.py"
    clean_dir = "/home/user/data/clean"
    evil_dir = "/home/user/data/evil"

    # Test Clean Corpus
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".csv")]
    clean_modified = []

    for cf in clean_files:
        input_csv = os.path.join(clean_dir, cf)
        output_csv = os.path.join(tmp_path, f"out_{cf}")

        with open(input_csv, "r") as f:
            original_rows = list(csv.DictReader(f))

        res = subprocess.run([sys.executable, script_path, "--input", input_csv, "--output", str(output_csv)], capture_output=True, text=True)
        assert res.returncode == 0, f"Script failed on clean file {cf}:\n{res.stderr}"

        with open(output_csv, "r") as f:
            output_rows = list(csv.DictReader(f))

        if len(output_rows) != len(original_rows):
            clean_modified.append(cf)

    # Test Evil Corpus
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".csv")]
    evil_bypassed = []

    for ef in evil_files:
        input_csv = os.path.join(evil_dir, ef)
        output_csv = os.path.join(tmp_path, f"out_{ef}")

        res = subprocess.run([sys.executable, script_path, "--input", input_csv, "--output", str(output_csv)], capture_output=True, text=True)
        assert res.returncode == 0, f"Script failed on evil file {ef}:\n{res.stderr}"

        with open(output_csv, "r") as f:
            output_rows = list(csv.DictReader(f))

        if len(output_rows) > 0:
            evil_bypassed.append(ef)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    if error_msgs:
        pytest.fail("; ".join(error_msgs))


VOCAB = "abcdefghijklmnopqrstuvwxyz "
REFERENCE = "SYSTEM PROMPT OVERRIDE"


def independent_embedding(text):
    lowered = str(text).lower()
    values = np.array([lowered.count(ch) for ch in VOCAB], dtype=float)
    norm = np.linalg.norm(values)
    return values / norm


def independent_correlation(text):
    a = independent_embedding(text)
    b = independent_embedding(REFERENCE)
    a_centered = a - a.mean()
    b_centered = b - b.mean()
    denominator = math.sqrt(float(np.dot(a_centered, a_centered) * np.dot(b_centered, b_centered)))
    return float(np.dot(a_centered, b_centered) / denominator)


def test_generated_csv_filtering_by_content(tmp_path):
    """Exercise filtering on unpredictable rows and verify exact output content."""
    script_path = "/home/user/filter_csv.py"
    rng = random.SystemRandom()
    rows = []

    # These have the same character-count embedding as the reference, but do
    # not contain the reference phrase and are randomized for every run.
    reference_chars = list(REFERENCE.lower())
    for i in range(8):
        middle = reference_chars[:]
        rng.shuffle(middle)
        text = "q" + "".join(middle) + "q"
        rows.append({"id": str(10000 + i), "text": text})

    # Generate unrelated, unpredictable texts. Expected decisions are derived
    # independently below rather than encoded by fixture path or row count.
    low_alphabet = string.ascii_lowercase
    for i in range(24):
        length = rng.randrange(12, 80)
        text = "".join(rng.choice(low_alphabet) for _ in range(length))
        rows.append({"id": str(20000 + i), "text": text})

    # Guaranteed low-correlation rows ensure that a header-only output fails.
    rows.extend([
        {"id": "30001", "text": "z" * rng.randrange(15, 45)},
        {"id": "30002", "text": "j" * rng.randrange(15, 45)},
    ])
    rng.shuffle(rows)

    expected = [row for row in rows if not (independent_correlation(row["text"]) > 0.85)]
    assert expected, "Generated corpus unexpectedly has no retained rows"
    assert len(expected) < len(rows), "Generated corpus unexpectedly has no dropped rows"

    input_csv = tmp_path / ("incoming_" + uuid.uuid4().hex + ".csv")
    output_csv = tmp_path / ("processed_" + uuid.uuid4().hex + ".csv")
    with open(input_csv, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["id", "text"])
        writer.writeheader()
        writer.writerows(rows)

    res = subprocess.run(
        [sys.executable, script_path, "--input", str(input_csv), "--output", str(output_csv)],
        capture_output=True,
        text=True,
    )
    assert res.returncode == 0, f"Script failed on generated corpus:\n{res.stderr}"
    assert output_csv.is_file(), "Script did not create the requested output file"

    with open(output_csv, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["id", "text"], "Output headers must be exactly id,text"
        actual = list(reader)

    assert actual == expected, "Output rows or ordering do not match correlation-based filtering"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
