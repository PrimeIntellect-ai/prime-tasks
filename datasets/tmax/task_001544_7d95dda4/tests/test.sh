#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import subprocess
import urllib.request
from collections import Counter

import redis


def parse_fasta(path):
    seqs = {}
    with open(path) as f:
        curr_id = None
        curr_seq = []
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                if curr_id:
                    seqs[curr_id] = "".join(curr_seq)
                curr_id = line[1:]
                curr_seq = []
            else:
                curr_seq.append(line)
        if curr_id:
            seqs[curr_id] = "".join(curr_seq)
    return seqs


def get_bg(path):
    with open(path) as f:
        return "".join(l.strip() for l in f if not l.startswith(">"))


def revcomp(seq):
    comp = {'A': 'T', 'T': 'A', 'C': 'G', 'G': 'C'}
    return "".join(comp.get(c, c) for c in reversed(seq))


def get_score(seq, bg):
    max_score = 0
    for i in range(len(bg) - len(seq)):
        score = sum(2 if seq[j] == bg[i+j] else -1 for j in range(len(seq)))
        if score > max_score:
            max_score = score
    return max_score


def post_score(seq):
    request = urllib.request.Request(
        "http://localhost:5000/score",
        data=json.dumps({"sequence": seq}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        assert response.status == 200, f"Alignment API returned HTTP {response.status}"
        return json.loads(response.read().decode())


def test_optimized_primers():
    csv_path = "/home/user/optimized_primers.csv"
    design_path = "/home/user/design.py"
    targets_path = "/home/user/targets.fasta"
    bg_path = "/home/user/background.fasta"

    assert os.path.isfile(design_path), f"Design script missing: {design_path}"
    assert os.path.getsize(design_path) > 0, f"Design script is empty: {design_path}"
    assert os.path.isfile(targets_path), f"Targets file missing: {targets_path}"
    assert os.path.isfile(bg_path), f"Background file missing: {bg_path}"

    targets = parse_fasta(targets_path)
    bg = get_bg(bg_path)
    assert len(targets) == 5, f"Expected 5 targets, found {len(targets)}"

    # Confirm Redis is running and that the live Flask API caches in database 0.
    redis0 = redis.Redis(host="localhost", port=6379, db=0, socket_timeout=5)
    redis1 = redis.Redis(host="localhost", port=6379, db=1, socket_timeout=5)
    assert redis0.ping(), "Redis is not running on localhost:6379"

    probe = "ACGTACGTACGTACGTACGT"
    redis0.delete(probe)
    redis1.delete(probe)
    probe_result = post_score(probe)
    assert probe_result.get("score") == get_score(probe, bg), "Alignment API returned an incorrect score"
    cached_probe = redis0.get(probe)
    assert cached_probe is not None, "Flask API is not configured to use Redis database 0"
    assert int(cached_probe) == get_score(probe, bg), "Flask API cached an incorrect score"
    assert redis1.get(probe) is None, "Flask API is using Redis database 1 instead of database 0"

    # Remove cached evidence and execute the submitted artifact. Its API queries
    # must repopulate database 0 for every valid candidate sequence.
    redis0.flushdb()
    if os.path.exists(csv_path):
        os.remove(csv_path)
    result = subprocess.run(
        ["python3", design_path],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"design.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(csv_path), f"Output file missing after running design.py: {csv_path}"

    candidates = set()
    for target in targets.values():
        for i in range(21):
            candidates.add(target[i:i + 20])
            candidates.add(revcomp(target[60 + i:60 + i + 20]))
    for candidate in candidates:
        cached = redis0.get(candidate)
        assert cached is not None, f"design.py did not query the API for candidate {candidate}"
        assert int(cached) == get_score(candidate, bg), f"Incorrect cached score for candidate {candidate}"

    total_score = 0
    count = 0
    rows = []

    with open(csv_path, newline="") as f:
        reader = csv.DictReader(f)
        assert "Target_ID" in reader.fieldnames, "Missing Target_ID column"
        assert "Forward_Primer" in reader.fieldnames, "Missing Forward_Primer column"
        assert "Reverse_Primer" in reader.fieldnames, "Missing Reverse_Primer column"
        assert reader.fieldnames == ["Target_ID", "Forward_Primer", "Reverse_Primer"], \
            "CSV must contain exactly the three required columns in the required order"

        for row in reader:
            rows.append(row)
            tid = row['Target_ID']
            fwd = row['Forward_Primer']
            rev = row['Reverse_Primer']

            assert tid in targets, f"Unknown Target_ID in CSV: {tid}"
            target = targets[tid]

            assert len(fwd) == 20, f"Forward primer for {tid} is not 20bp"
            assert len(rev) == 20, f"Reverse primer for {tid} is not 20bp"

            assert fwd in target[:40], f"Forward primer for {tid} is not a valid substring of the first 40bp"
            assert revcomp(rev) in target[60:], f"Reverse primer for {tid} is not a valid reverse complement of the last 40bp"

            total_score += get_score(fwd, bg)
            total_score += get_score(rev, bg)
            count += 2

    id_counts = Counter(row['Target_ID'] for row in rows)
    assert set(id_counts) == set(targets), "CSV must contain every target ID"
    assert all(id_counts[tid] == 1 for tid in targets), "Each target ID must appear exactly once"
    assert count == 10, f"Expected 10 primers (5 targets * 2), found {count}"
    assert total_score <= 180, f"Total off-target score {total_score} exceeds threshold of 180"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
