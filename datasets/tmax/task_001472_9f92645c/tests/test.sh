#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import urllib.parse
import urllib.request

import pytest

AGENT_SCRIPT = "/home/user/dataset_recommender.sh"


def fetch_json(url):
    with urllib.request.urlopen(url, timeout=5) as response:
        return json.load(response)


def features(dataset_id):
    query = urllib.parse.urlencode({"id": dataset_id})
    return fetch_json(f"http://127.0.0.1:5001/features?{query}")


def expected_output(input_text):
    output = []
    for line in input_text.splitlines():
        fields = line.split()
        if not fields:
            continue

        query_id, threshold_text = fields[0], fields[1]
        threshold = float(threshold_text)
        query_vector = [0.0 if value is None else float(value) for value in features(query_id)]
        candidates = fetch_json("http://127.0.0.1:5002/candidates")
        mean_query = sum(query_vector) / len(query_vector)
        rows = []

        for candidate_id in candidates:
            candidate_vector = [
                0.0 if value is None else float(value)
                for value in features(candidate_id)
            ]
            mean_candidate = sum(candidate_vector) / len(candidate_vector)
            covariance = sum(
                (x - mean_query) * (y - mean_candidate)
                for x, y in zip(query_vector, candidate_vector)
            ) / len(query_vector)

            if covariance >= threshold:
                formatted = f"{covariance:.3f}"
                rows.append((candidate_id, formatted))

        # The reference sorts by the displayed numeric covariance, then ID.
        rows.sort(key=lambda row: (-float(row[1]), row[0]))
        output.extend(
            f"{query_id} -> {candidate_id}: {formatted}"
            for candidate_id, formatted in rows
        )

    return "".join(line + "\n" for line in output)


def run_agent(input_text):
    return subprocess.run(
        [AGENT_SCRIPT],
        input=input_text,
        text=True,
        capture_output=True,
        timeout=60,
    ).stdout


def test_agent_script_exists_and_executable():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable."


def test_services_and_nonempty_case():
    assert len(features("DS100")) == 20
    assert fetch_json("http://127.0.0.1:5002/candidates") == [
        f"DS{i:03d}" for i in range(100, 120)
    ]

    test_input = "DS100 -1000.00\n"
    expected = expected_output(test_input)
    assert expected, "The deterministic validation case unexpectedly produced no output."
    assert run_agent(test_input) == expected


def generate_fuzz_input(lines_per_run=5):
    lines = []
    for _ in range(lines_per_run):
        ds_id = f"DS{random.randint(0, 999):03d}"
        threshold = f"{random.randint(0, 9)}.{random.randint(0, 99):02d}"
        lines.append(f"{ds_id} {threshold}")
    return "\n".join(lines) + "\n"


def test_fuzz_equivalence():
    random.seed(42)
    iterations = 20
    lines_per_run = 5

    for i in range(iterations):
        fuzz_input = generate_fuzz_input(lines_per_run)
        expected = expected_output(fuzz_input)
        agent_stdout = run_agent(fuzz_input)

        if expected != agent_stdout:
            pytest.fail(
                f"Mismatch on iteration {i + 1}.\n\n"
                f"Input:\n{fuzz_input}\n"
                f"Expected Output:\n{expected}\n"
                f"Agent Output:\n{agent_stdout}\n"
            )
TEST_EOF

python3 /app/feature_store.py >/tmp/feature_store.log 2>&1 &
FEATURE_PID=$!
python3 /app/candidate_catalog.py >/tmp/candidate_catalog.log 2>&1 &
CATALOG_PID=$!

cleanup() {
    kill "$FEATURE_PID" "$CATALOG_PID" 2>/dev/null || true
    wait "$FEATURE_PID" "$CATALOG_PID" 2>/dev/null || true
}
trap cleanup EXIT

ready=0
for _ in $(seq 1 50); do
    if curl -fsS 'http://127.0.0.1:5001/' >/dev/null 2>&1 && \
       curl -fsS 'http://127.0.0.1:5002/candidates' >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 0.1
done

if [ "$ready" -eq 1 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
