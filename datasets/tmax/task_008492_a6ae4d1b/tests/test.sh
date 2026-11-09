#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess
import pytest

ANALYZE_FILE = "/home/user/analyze.go"
INPUT_FILE = "/home/user/transactions.json"
OUTPUT_FILE = "/home/user/deadlock_report.json"


def run_analyzer():
    if os.path.lexists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    subprocess.run(
        ["go", "run", ANALYZE_FILE],
        cwd="/home/user",
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing. Did you run your Go program?"
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} should be a file."


def expected_report(transactions):
    tx_map = {t["tx_id"]: t for t in transactions}
    graph = {t["tx_id"]: t["waiting_for_tx"] for t in transactions if t["waiting_for_tx"] is not None}
    visited = set()
    cycle_nodes = set()

    for node in graph:
        if node in visited:
            continue
        curr = node
        curr_path = []
        while curr is not None and curr not in visited:
            visited.add(curr)
            curr_path.append(curr)
            curr = graph.get(curr)
        if curr is not None and curr in curr_path:
            idx = curr_path.index(curr)
            cycle_nodes.update(curr_path[idx:])
            break

    assert cycle_nodes, "No cycle found in the input data, but one was expected."
    filtered_txs = [tx_map[node] for node in cycle_nodes if tx_map[node]["duration"] >= 60]
    filtered_txs.sort(key=lambda x: (-x["duration"], x["tx_id"]))
    return filtered_txs[:2]


def load_actual_output():
    with open(OUTPUT_FILE, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_FILE} does not contain valid JSON.")


def test_analyze_go_exists_and_is_a_regular_source_file():
    assert os.path.exists(ANALYZE_FILE), f"Required Go program {ANALYZE_FILE} is missing."
    assert os.path.isfile(ANALYZE_FILE), f"{ANALYZE_FILE} should be a regular file."
    assert not os.path.islink(ANALYZE_FILE), f"{ANALYZE_FILE} must not be a symbolic link."


def test_deadlock_report_exists_and_correct():
    input_file = "/home/user/transactions.json"
    output_file = "/home/user/deadlock_report.json"

    # Remove any prewritten report and require the submitted Go program to generate it.
    run_analyzer()

    assert os.path.exists(output_file), f"Output file {output_file} is missing. Did you run your Go program?"
    assert os.path.isfile(output_file), f"{output_file} should be a file."

    assert os.path.exists(input_file), f"Input file {input_file} is missing."
    with open(input_file, "r") as f:
        transactions = json.load(f)

    # Build graph and transaction map
    tx_map = {t["tx_id"]: t for t in transactions}
    graph = {t["tx_id"]: t["waiting_for_tx"] for t in transactions if t["waiting_for_tx"] is not None}

    # Find the cycle using DFS
    visited = set()
    cycle_nodes = set()

    for node in graph:
        if node in visited:
            continue
        curr = node
        curr_path = []
        while curr is not None and curr not in visited:
            visited.add(curr)
            curr_path.append(curr)
            curr = graph.get(curr)

        if curr is not None and curr in curr_path:
            # Cycle detected
            idx = curr_path.index(curr)
            cycle_nodes.update(curr_path[idx:])
            break  # The instructions specify exactly one cycle

    assert cycle_nodes, "No cycle found in the input data, but one was expected."

    # Filter cycle nodes by duration >= 60
    filtered_txs = [tx_map[node] for node in cycle_nodes if tx_map[node]["duration"] >= 60]

    # Sort primarily by duration DESC, then by tx_id ASC
    filtered_txs.sort(key=lambda x: (-x["duration"], x["tx_id"]))

    # Paginate (top 2)
    expected_output = filtered_txs[:2]

    with open(output_file, "r") as f:
        try:
            actual_output = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_file} does not contain valid JSON.")

    assert isinstance(actual_output, list), f"Expected the output to be a JSON array, got {type(actual_output).__name__}."
    assert actual_output == expected_output, (
        f"The contents of {output_file} do not match the expected deadlock report.\n"
        f"Expected: {json.dumps(expected_output, indent=2)}\n"
        f"Actual: {json.dumps(actual_output, indent=2)}"
    )


def test_go_program_handles_unseen_wait_graphs():
    with open(INPUT_FILE, "rb") as f:
        original_input = f.read()

    rng = random.Random(secrets.randbits(128))
    try:
        for case_num in range(3):
            ids = rng.sample(range(1000, 9000), 9)
            cycle_ids = ids[:6]
            durations = [59, 60, 75, 110, 110, 140]
            rng.shuffle(durations)
            transactions = []

            for i, tx_id in enumerate(cycle_ids):
                transactions.append({
                    "tx_id": tx_id,
                    "waiting_for_tx": cycle_ids[(i + 1) % len(cycle_ids)],
                    "duration": durations[i],
                    "query": f"cycle_{case_num}_{secrets.token_hex(5)}",
                })

            transactions.extend([
                {
                    "tx_id": ids[6],
                    "waiting_for_tx": cycle_ids[rng.randrange(len(cycle_ids))],
                    "duration": rng.randint(150, 300),
                    "query": f"outside_{secrets.token_hex(5)}",
                },
                {
                    "tx_id": ids[7],
                    "waiting_for_tx": ids[6],
                    "duration": rng.randint(60, 250),
                    "query": f"chain_{secrets.token_hex(5)}",
                },
                {
                    "tx_id": ids[8],
                    "waiting_for_tx": None,
                    "duration": rng.randint(200, 400),
                    "query": f"idle_{secrets.token_hex(5)}",
                },
            ])
            rng.shuffle(transactions)
            expected = expected_report(transactions)

            with open(INPUT_FILE, "w") as f:
                json.dump(transactions, f)
            run_analyzer()
            actual = load_actual_output()

            assert isinstance(actual, list), f"Expected the output to be a JSON array, got {type(actual).__name__}."
            assert actual == expected, (
                "The Go program produced an incorrect report for an unseen waits-for graph.\n"
                f"Expected: {json.dumps(expected, indent=2)}\n"
                f"Actual: {json.dumps(actual, indent=2)}"
            )
    finally:
        with open(INPUT_FILE, "wb") as f:
            f.write(original_input)
        run_analyzer()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
