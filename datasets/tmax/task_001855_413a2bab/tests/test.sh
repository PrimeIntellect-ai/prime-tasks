#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess

import pytest
import requests


def get_fasta_dict(filepath):
    sequences = {}
    with open(filepath, "r") as f:
        header = None
        seq = []
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                if header:
                    sequences[header] = "".join(seq)
                header = line[1:]
                seq = []
            else:
                seq.append(line)
        if header:
            sequences[header] = "".join(seq)
    return sequences


def source_score(s1, s2):
    return sum(3 if a == b else -1 for a, b in zip(s1, s2))


def run_aligner(s1, s2):
    result = subprocess.run(
        ["/app/aligner", s1, s2],
        capture_output=True,
        text=True,
        timeout=2,
    )
    assert result.returncode == 0, f"aligner exited with {result.returncode}: {result.stderr}"
    output = result.stdout.strip()
    assert re.fullmatch(r"-?[0-9]+", output), f"Invalid aligner output: {result.stdout!r}"
    return int(output)


def test_aligner_compiled():
    aligner_path = "/app/aligner"
    assert os.path.isfile(aligner_path), f"Executable not found at {aligner_path}"
    assert os.access(aligner_path, os.X_OK), f"File at {aligner_path} is not executable"
    with open(aligner_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The aligner must be a compiled native executable"


def test_aligner_matches_supplied_c_program():
    fixed_cases = [
        ("", ""),
        ("A", "A"),
        ("A", "T"),
        ("ATGC", "ATGC"),
        ("ATGC", "ATGA"),
        ("AAAA", "TTTT"),
        ("ACGT", "AC"),
        ("AC", "ACGT"),
        ("ATGCGTACGTTAGC", "ATGCGTACGTTAGA"),
    ]
    for s1, s2 in fixed_cases:
        assert run_aligner(s1, s2) == source_score(s1, s2)

    rng = random.SystemRandom()
    alphabet = "ACGT"
    for _ in range(64):
        s1 = "".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 81)))
        s2 = "".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 81)))
        assert run_aligner(s1, s2) == source_score(s1, s2)

    missing_args = subprocess.run(["/app/aligner"], capture_output=True, timeout=2)
    assert missing_args.returncode == 1, "aligner must implement the supplied program's argc check"


def test_http_server_and_logic():
    aligner_path = "/app/aligner"

    # Recompute using the executable, retaining the original integration check.
    db_seqs = get_fasta_dict("/app/database.fasta")
    ref_seq = db_seqs.get("seq_8492")
    assert ref_seq, "Reference sequence >seq_8492 not found in database.fasta"

    query_seqs = get_fasta_dict("/app/queries.fasta")
    best_query = None
    best_score = -float("inf")
    for q_header, q_seq in query_seqs.items():
        try:
            result = subprocess.run(
                [aligner_path, ref_seq, q_seq],
                capture_output=True,
                text=True,
                check=True,
                timeout=2,
            )
            score = int(result.stdout.strip())
            if score > best_score:
                best_score = score
                best_query = q_header
        except Exception as e:
            pytest.fail(f"Failed to run {aligner_path} or parse its output: {e}")

    executable_expected_body = f"{best_query}:{best_score}"

    # Independently derive the result from the semantics of the supplied C source.
    oracle_query = None
    oracle_score = -float("inf")
    for q_header, q_seq in query_seqs.items():
        score = source_score(ref_seq, q_seq)
        if score > oracle_score:
            oracle_score = score
            oracle_query = q_header
    expected_body = f"{oracle_query}:{oracle_score}"
    assert executable_expected_body == expected_body, "aligner produced an incorrect winning result"

    url = "http://127.0.0.1:9090/result"

    try:
        resp = requests.get(url, timeout=2)
        assert resp.status_code == 401, f"Expected 401 Unauthorized without auth, got {resp.status_code}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"HTTP server not responding or error without auth: {e}")

    try:
        resp = requests.get(url, headers={"Authorization": "Bearer 1234"}, timeout=2)
        assert resp.status_code == 401, f"Expected 401 Unauthorized with bad auth, got {resp.status_code}"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"HTTP server error with bad auth: {e}")

    try:
        resp = requests.get(url, headers={"Authorization": "Bearer 8492"}, timeout=2)
        assert resp.status_code == 200, f"Expected 200 OK with correct auth, got {resp.status_code}"
        assert resp.text.strip() == executable_expected_body, f"Expected response body '{executable_expected_body}', got '{resp.text.strip()}'"
        assert resp.text.strip() == expected_body, f"Expected independently computed body '{expected_body}', got '{resp.text.strip()}'"
    except requests.exceptions.RequestException as e:
        pytest.fail(f"HTTP server error with correct auth: {e}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
