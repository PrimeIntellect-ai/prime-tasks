#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import json
import os
import random
import re
import secrets
import subprocess

import pytest
import requests
from nbclient import NotebookClient

EXPECTED_NOTEBOOK_SOURCE = """import csv
import os
import re
import statistics

assert os.path.exists('/app/target_sequence.txt'), 'Target sequence file not found'
with open('/app/target_sequence.txt', 'r') as f:
    seq = f.read().strip()
assert re.fullmatch(r'[ACGT]+', seq), f'Invalid sequence extracted: {seq}'

with open('/app/candidates.csv', newline='') as f:
    candidates = [(primer_id, candidate) for primer_id, candidate in csv.reader(f)]
assert candidates, 'Candidate dataset is empty'
lengths = [len(candidate) for _, candidate in candidates]
scores = [sum(a == b for a, b in zip(seq, candidate)) for _, candidate in candidates]
assert min(lengths) <= len(seq) <= max(lengths), 'Extracted sequence length is outside the candidate distribution'
assert all(0 <= score <= min(len(seq), length) for score, length in zip(scores, lengths))
assert statistics.mean(scores) >= 0
print('Regression test passed.')
"""


def extract_sequence_from_image():
    result = subprocess.run(
        ["tesseract", "/app/reference_gel.png", "stdout", "--psm", "6"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    match = re.search(r"TARGET[_ ]SEQ\s*:\s*([ACGT]+)", result.stdout.upper())
    assert match, f"Could not derive TARGET_SEQ from reference image; OCR output was {result.stdout!r}"
    return match.group(1)


def test_target_sequence_file():
    path = "/app/target_sequence.txt"
    assert os.path.isfile(path), f"File {path} is missing."
    with open(path, "r") as f:
        content = f.read().strip()
    expected = extract_sequence_from_image()
    assert content == expected, f"Expected OCR-derived target sequence {expected!r}, but got {content!r}."


def test_regression_notebook_executed_and_reexecutes():
    path = "/app/regression.ipynb"
    assert os.path.isfile(path), f"File {path} is missing."

    with open(path, "r") as f:
        try:
            nb = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} is not a valid JSON/Jupyter notebook.")

    code_cells = [cell for cell in nb.get("cells", []) if cell.get("cell_type") == "code"]
    assert code_cells, f"The notebook {path} has no code cells."
    assert "".join(code_cells[0].get("source", [])) == EXPECTED_NOTEBOOK_SOURCE, "The regression test code was altered."

    executed = any(cell.get("execution_count") is not None for cell in code_cells)
    assert executed, f"The notebook {path} does not appear to have been executed (no execution counts found)."
    recorded_output = "".join(
        output.get("text", "") if isinstance(output.get("text", ""), str) else "".join(output.get("text", []))
        for cell in code_cells
        for output in cell.get("outputs", [])
        if output.get("output_type") == "stream"
    )
    assert "Regression test passed." in recorded_output, "The in-place notebook lacks the successful regression output."

    trial = copy.deepcopy(nb)
    for cell in trial.get("cells", []):
        if cell.get("cell_type") == "code":
            cell["execution_count"] = None
            cell["outputs"] = []
    try:
        NotebookClient(trial, timeout=60, kernel_name="python3").execute(cwd="/app")
    except Exception as exc:
        pytest.fail(f"The regression notebook fails when independently executed: {exc}")

    fresh_output = "".join(
        output.get("text", "") if isinstance(output.get("text", ""), str) else "".join(output.get("text", []))
        for cell in trial.get("cells", [])
        for output in cell.get("outputs", [])
        if output.get("output_type") == "stream"
    )
    assert "Regression test passed." in fresh_output


def request_optimizer(min_len):
    url = f"http://127.0.0.1:8080/optimize?min_len={min_len}"
    try:
        response = requests.get(url, timeout=5)
    except requests.RequestException as exc:
        pytest.fail(f"Failed to connect to the optimization service at {url}: {exc}")
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    return response


def test_bash_optimization_service_16():
    response = request_optimizer(16)
    assert "ID_001" in response.text, f"Expected 'ID_001' in response, got {response.text!r}"


def test_bash_optimization_service_18():
    response = request_optimizer(18)
    assert "ID_005" in response.text, f"Expected 'ID_005' in response, got {response.text!r}"


def test_bash_optimization_service_14():
    response = request_optimizer(14)
    assert "ID_001" in response.text, f"Expected 'ID_001' in response, got {response.text!r}"


def test_service_uses_live_data_filtering_alignment_and_ties():
    target_path = "/app/target_sequence.txt"
    candidates_path = "/app/candidates.csv"
    with open(target_path, "rb") as f:
        original_target = f.read()
    with open(candidates_path, "rb") as f:
        original_candidates = f.read()

    alphabet = "ACGT"
    target = "".join(secrets.choice(alphabet) for _ in range(24))

    def different(base):
        return next(ch for ch in alphabet if ch != base)

    def sequence_with_score(score, total_length):
        prefix = target[:score]
        mismatches = "".join(different(ch) for ch in target[score:])
        suffix = "".join(secrets.choice(alphabet) for _ in range(max(0, total_length - len(target))))
        return (prefix + mismatches + suffix)[:total_length]

    long_first = "DYN_LONG_" + secrets.token_hex(8)
    long_tie = "DYN_LONG_TIE_" + secrets.token_hex(8)
    medium_first = "DYN_MEDIUM_" + secrets.token_hex(8)
    medium_tie = "DYN_MEDIUM_TIE_" + secrets.token_hex(8)
    short_best = "DYN_SHORT_" + secrets.token_hex(8)
    distractor = "DYN_DISTRACTOR_" + secrets.token_hex(8)

    rows = [
        (long_first, sequence_with_score(5, 40)),
        (long_tie, sequence_with_score(5, 40)),
        (medium_first, sequence_with_score(18, 30)),
        (medium_tie, sequence_with_score(18, 30)),
        (short_best, target),
        (distractor, sequence_with_score(3, 12)),
    ]

    try:
        with open(target_path, "w") as f:
            f.write(target + "\n")
        with open(candidates_path, "w", newline="") as f:
            for primer_id, sequence in rows:
                f.write(f"{primer_id},{sequence}\n")

        thresholds = [1, 12, 24, 25, 27, 30, 31, 35, 40]
        thresholds.extend([random.randint(1, 24), random.randint(25, 30), random.randint(31, 40)])
        random.shuffle(thresholds)

        for min_len in thresholds:
            valid = [(primer_id, sequence) for primer_id, sequence in rows if len(sequence) >= min_len]
            assert valid
            scores = [sum(a == b for a, b in zip(target, sequence)) for _, sequence in valid]
            expected = valid[scores.index(max(scores))][0]

            response = request_optimizer(min_len)
            assert response.headers.get("Content-Type", "").split(";", 1)[0].strip().lower() == "text/plain"
            assert response.headers.get("Content-Length") is not None, "Missing Content-Length header"
            assert int(response.headers["Content-Length"]) == len(response.content), "Incorrect Content-Length header"
            assert response.text.strip() == expected, (
                f"For min_len={min_len}, expected exactly {expected!r}, got {response.text!r}"
            )
    finally:
        with open(target_path, "wb") as f:
            f.write(original_target)
        with open(candidates_path, "wb") as f:
            f.write(original_candidates)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
