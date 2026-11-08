#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

CSV_PATH = "/home/user/waits_for.csv"
CPP_PATH = "/home/user/solve.cpp"
JSON_PATH = "/home/user/deadlock.json"
BIN_PATH = f"/tmp/solve_submission_{os.getpid()}"


def load_output():
    assert os.path.isfile(JSON_PATH), f"The file {JSON_PATH} does not exist. Did you run your C++ program?"
    try:
        with open(JSON_PATH, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        raise AssertionError(f"The file {JSON_PATH} does not contain valid JSON: {e}")
    assert isinstance(data, list), f"The JSON in {JSON_PATH} should be an array."
    assert all(type(x) is int for x in data), "Every transaction ID must be a JSON integer."
    assert all(data[i] < data[i + 1] for i in range(len(data) - 1)), \
        "Transaction IDs must be sorted in strictly ascending order."
    return data


def oracle(edges):
    nodes = sorted({x for edge in edges for x in edge})
    graph = {x: [] for x in nodes}
    for a, b in edges:
        if b not in graph[a]:
            graph[a].append(b)

    cycles = set()
    for start in nodes:
        def dfs(cur, path, seen):
            for nxt in graph[cur]:
                if nxt == start:
                    cycles.add((len(path), tuple(sorted(path))))
                elif nxt not in seen:
                    dfs(nxt, path + [nxt], seen | {nxt})
        dfs(start, [start], {start})

    assert cycles, "Internal verifier case unexpectedly has no cycle"
    shortest_length = min(length for length, _ in cycles)
    shortest = {vertices for length, vertices in cycles if length == shortest_length}
    smallest_id = min(vertices[0] for vertices in shortest)
    chosen = {vertices for vertices in shortest if vertices[0] == smallest_id}
    assert len(chosen) == 1, "Internal verifier case has an ambiguous tie"
    return list(next(iter(chosen)))


def write_case(edges):
    rows = list(edges)
    secrets.SystemRandom().shuffle(rows)
    with open(CSV_PATH, "w") as f:
        f.write("waiter_tx,holder_tx\n")
        for a, b in rows:
            f.write(f"{a},{b}\n")


def run_program():
    if os.path.exists(JSON_PATH):
        os.unlink(JSON_PATH)
    result = subprocess.run(
        [BIN_PATH], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, \
        f"Compiled program exited with status {result.returncode}. stderr: {result.stderr}"
    return load_output()


def fresh_ids(count):
    values = set()
    while len(values) < count:
        values.add(1000 + secrets.randbelow(900000000))
    return list(values)


def main():
    # Preserve the original verifier's assertions about submitted artifacts.
    assert os.path.isfile(CPP_PATH), \
        f"The file {CPP_PATH} does not exist. You must write your solution in this file."
    initial = load_output()
    assert initial == [13, 14], \
        f"The cycle detected is incorrect. Expected [13, 14], got {initial}."

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()
    original_json_exists = os.path.exists(JSON_PATH)
    original_json = None
    if original_json_exists:
        with open(JSON_PATH, "rb") as f:
            original_json = f.read()

    try:
        compiled = subprocess.run(
            ["g++", "-std=c++17", "-O2", CPP_PATH, "-o", BIN_PATH],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
        )
        assert compiled.returncode == 0, f"solve.cpp failed to compile: {compiled.stderr}"
        assert os.path.isfile(BIN_PATH) and os.access(BIN_PATH, os.X_OK), \
            "Compilation did not produce an executable."

        # Re-run the submitted program on the supplied graph.
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        supplied_result = run_program()
        assert supplied_result == [13, 14], \
            f"Program produced {supplied_result} for the supplied graph; expected [13, 14]."

        cases = []

        ids = fresh_ids(9)
        cases.append([
            (ids[0], ids[1]), (ids[1], ids[2]), (ids[2], ids[0]),
            (ids[3], ids[4]), (ids[4], ids[3]),
            (ids[5], ids[6]), (ids[6], ids[7]), (ids[7], ids[8]),
        ])

        ids = sorted(fresh_ids(7))
        cases.append([
            (ids[0], ids[6]), (ids[6], ids[0]),
            (ids[2], ids[3]), (ids[3], ids[2]),
            (ids[1], ids[4]), (ids[4], ids[5]),
        ])

        ids = fresh_ids(6)
        cases.append([
            (ids[0], ids[0]),
            (ids[1], ids[2]), (ids[2], ids[1]),
            (ids[3], ids[4]), (ids[4], ids[5]),
        ])

        ids = fresh_ids(8)
        cases.append([
            (ids[0], ids[1]), (ids[1], ids[2]),
            (ids[2], ids[3]), (ids[3], ids[0]),
            (ids[4], ids[5]), (ids[5], ids[6]), (ids[6], ids[7]),
        ])

        for index, edges in enumerate(cases, 1):
            expected = oracle(edges)
            write_case(edges)
            actual = run_program()
            assert actual == expected, \
                f"Dynamic graph case {index}: expected {expected}, got {actual}."
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        if original_json_exists:
            with open(JSON_PATH, "wb") as f:
                f.write(original_json)
        elif os.path.exists(JSON_PATH):
            os.unlink(JSON_PATH)
        if os.path.exists(BIN_PATH):
            os.unlink(BIN_PATH)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
