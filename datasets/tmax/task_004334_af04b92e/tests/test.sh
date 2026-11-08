#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

SOURCE = "/home/user/detect.go"
INPUT = "/home/user/transactions.jsonl"
OUTPUT = "/home/user/deadlocks.json"


def run_program():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        ["go", "run", SOURCE],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Go program failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing. Did you run your Go program?"


def load_and_validate_output(expected):
    with open(OUTPUT, "r") as f:
        try:
            output_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {OUTPUT} does not contain valid JSON."

    assert isinstance(output_data, dict), f"Expected JSON object, got {type(output_data).__name__}"
    assert "deadlocked_transactions" in output_data, "Key 'deadlocked_transactions' is missing from the output JSON."
    assert set(output_data.keys()) == {"deadlocked_transactions"}, "Output JSON must contain exactly the key 'deadlocked_transactions'."

    actual_deadlocks = output_data["deadlocked_transactions"]
    assert isinstance(actual_deadlocks, list), f"Expected 'deadlocked_transactions' to be a list, got {type(actual_deadlocks).__name__}"
    assert actual_deadlocks == expected, f"Deadlocked transactions mismatch. Expected {expected}, got {actual_deadlocks}"


def original_expected_deadlocks():
    assert os.path.isfile(INPUT), f"Input file {INPUT} is missing."

    acquired = {}
    waiting = {}
    with open(INPUT, "r") as f:
        for line in f:
            if not line.strip():
                continue
            event = json.loads(line)
            tx = event["tx_id"]
            action = event["action"]
            res = event["resource"]
            if action == "ACQUIRED":
                acquired[res] = tx
            elif action == "WAITING":
                if tx not in waiting:
                    waiting[tx] = []
                waiting[tx].append(res)

    graph = {}
    for tx, res_list in waiting.items():
        for res in res_list:
            if res in acquired:
                target_tx = acquired[res]
                if tx not in graph:
                    graph[tx] = []
                graph[tx].append(target_tx)

    def find_cycles(graph):
        visited = set()
        rec_stack = set()
        deadlocked = set()

        def dfs(node, path):
            visited.add(node)
            rec_stack.add(node)
            path.append(node)
            for neighbor in graph.get(node, []):
                if neighbor not in visited:
                    dfs(neighbor, path)
                elif neighbor in rec_stack:
                    cycle_start_idx = path.index(neighbor)
                    for n in path[cycle_start_idx:]:
                        deadlocked.add(n)
            rec_stack.remove(node)
            path.pop()

        for node in list(graph.keys()) + list(acquired.values()):
            if node not in visited:
                dfs(node, [])
        return sorted(list(deadlocked))

    return find_cycles(graph)


def expected_from_events(events):
    acquired = {}
    graph = {}
    nodes = set()
    for event in events:
        nodes.add(event["tx_id"])
        if event["action"] == "ACQUIRED":
            acquired[event["resource"]] = event["tx_id"]
    for event in events:
        if event["action"] == "WAITING" and event["resource"] in acquired:
            graph.setdefault(event["tx_id"], set()).add(acquired[event["resource"]])
            nodes.add(acquired[event["resource"]])

    deadlocked = set()
    for start in nodes:
        stack = list(graph.get(start, ()))
        seen = set()
        while stack:
            node = stack.pop()
            if node == start:
                deadlocked.add(start)
                break
            if node not in seen:
                seen.add(node)
                stack.extend(graph.get(node, ()))
    return sorted(deadlocked)


def write_events(events):
    with open(INPUT, "w") as f:
        for event in events:
            f.write(json.dumps(event) + "\n")


def make_hidden_case():
    tag = secrets.token_hex(6)
    cycle_count = 4 + secrets.randbelow(4)
    cycle = [f"C_{tag}_{i}" for i in range(cycle_count)]
    tail = [f"T_{tag}_{i}" for i in range(3)]
    holders = cycle + tail
    resources = {tx: f"R_{tag}_{i}" for i, tx in enumerate(holders)}
    events = []
    timestamp = 1000

    for tx in holders:
        events.append({"tx_id": tx, "action": "ACQUIRED", "resource": resources[tx], "timestamp": timestamp})
        timestamp += 1
    for i, tx in enumerate(cycle):
        events.append({"tx_id": tx, "action": "WAITING", "resource": resources[cycle[(i + 1) % len(cycle)]], "timestamp": timestamp})
        timestamp += 1

    events.append({"tx_id": tail[0], "action": "WAITING", "resource": resources[cycle[0]], "timestamp": timestamp})
    timestamp += 1
    events.append({"tx_id": tail[1], "action": "WAITING", "resource": resources[tail[0]], "timestamp": timestamp})
    timestamp += 1
    events.append({"tx_id": tail[2], "action": "WAITING", "resource": f"UNOWNED_{tag}", "timestamp": timestamp})
    return events


def make_two_cycle_case():
    tag = secrets.token_hex(6)
    groups = [
        [f"A_{tag}_{i}" for i in range(3)],
        [f"B_{tag}_{i}" for i in range(2)],
    ]
    chain = [f"N_{tag}_{i}" for i in range(3)]
    all_txs = groups[0] + groups[1] + chain
    resources = {tx: f"RES_{tag}_{i}" for i, tx in enumerate(all_txs)}
    events = []
    timestamp = 2000

    for tx in all_txs:
        events.append({"tx_id": tx, "action": "ACQUIRED", "resource": resources[tx], "timestamp": timestamp})
        timestamp += 1
    for group in groups:
        for i, tx in enumerate(group):
            events.append({"tx_id": tx, "action": "WAITING", "resource": resources[group[(i + 1) % len(group)]], "timestamp": timestamp})
            timestamp += 1
    events.append({"tx_id": chain[0], "action": "WAITING", "resource": resources[groups[1][0]], "timestamp": timestamp})
    timestamp += 1
    events.append({"tx_id": chain[1], "action": "WAITING", "resource": resources[chain[0]], "timestamp": timestamp})
    return events


def test_go_program_and_deadlock_detection():
    assert os.path.isfile(SOURCE), f"Required Go source file {SOURCE} is missing."
    assert os.path.isfile(INPUT), f"Input file {INPUT} is missing."

    with open(INPUT, "rb") as f:
        original_input = f.read()

    try:
        # Execute the submitted program on the original input, then retain all
        # assertions from the original verifier.
        run_program()
        load_and_validate_output(original_expected_deadlocks())

        # Exercise the implementation on unpredictable graphs so a fixed output
        # cannot satisfy the verifier.
        for events in (make_hidden_case(), make_two_cycle_case()):
            write_events(events)
            expected = expected_from_events(events)
            run_program()
            load_and_validate_output(expected)
    finally:
        with open(INPUT, "wb") as f:
            f.write(original_input)
        # Leave the required report corresponding to the original task input.
        subprocess.run(
            ["go", "run", SOURCE],
            cwd="/home/user",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=30,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
