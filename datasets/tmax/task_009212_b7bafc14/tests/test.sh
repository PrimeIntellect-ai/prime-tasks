#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess

PROJECT_DIR = "/home/user/deadlock_analyzer"
INPUT_PATH = "/home/user/transactions.json"
REPORT_PATH = "/home/user/deadlock_report.csv"


def test_deadlock_report_exists_and_correct():
    # Preserve the original fixed-dataset assertion.
    assert os.path.isfile(REPORT_PATH), f"Expected output file {REPORT_PATH} is missing."

    with open(REPORT_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "tx_id,out_degree",
        "T11,3",
        "T2,2",
        "T3,2",
        "T6,2",
        "T1,1",
    ]

    assert lines == expected_lines, (
        f"Contents of {REPORT_PATH} do not match the expected output.\n"
        f"Expected: {expected_lines}\n"
        f"Got: {lines}"
    )


def test_rust_project_exists():
    cargo_toml = os.path.join(PROJECT_DIR, "Cargo.toml")

    assert os.path.isdir(PROJECT_DIR), f"Rust project directory {PROJECT_DIR} is missing."
    assert os.path.isfile(cargo_toml), f"Cargo.toml is missing in {PROJECT_DIR}. Did you use Cargo to create the project?"

    rust_sources = []
    for root, _, files in os.walk(PROJECT_DIR):
        for name in files:
            if name.endswith(".rs"):
                rust_sources.append(os.path.join(root, name))
    assert rust_sources, f"No Rust source files were found in {PROJECT_DIR}."


def expected_report(events):
    nodes = set()
    adjacency = {}
    for event in events:
        source = event["tx_id"]
        target = event["waits_for"]
        nodes.add(source)
        nodes.add(target)
        adjacency.setdefault(source, set()).add(target)
        adjacency.setdefault(target, set())

    def reachable(start):
        seen = set()
        stack = list(adjacency[start])
        while stack:
            node = stack.pop()
            if node in seen:
                continue
            seen.add(node)
            stack.extend(adjacency[node] - seen)
        return seen

    reachability = {node: reachable(node) for node in nodes}
    cyclic = []
    for node in nodes:
        in_cycle = node in adjacency[node]
        if not in_cycle:
            in_cycle = any(
                other != node
                and other in reachability[node]
                and node in reachability[other]
                for other in nodes
            )
        if in_cycle:
            cyclic.append((node, len(adjacency[node])))

    cyclic.sort(key=lambda item: (-item[1], item[0]))
    return ["tx_id,out_degree"] + [f"{tx_id},{degree}" for tx_id, degree in cyclic[:5]]


def run_analyzer(events):
    with open(INPUT_PATH, "w") as f:
        json.dump(events, f)

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", os.path.join(PROJECT_DIR, "Cargo.toml")],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert result.returncode == 0, f"The Rust analyzer failed to run:\n{result.stdout}"
    assert os.path.isfile(REPORT_PATH), "The executed analyzer did not create deadlock_report.csv."

    with open(REPORT_PATH, "r") as f:
        actual = [line.strip() for line in f if line.strip()]
    expected = expected_report(events)
    assert actual == expected, (
        "Analyzer output was incorrect for a verifier-generated input.\n"
        f"Expected: {expected}\nGot: {actual}\nProgram output:\n{result.stdout}"
    )


def test_build_and_execute_analyzer_on_derived_inputs():
    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()

    build = subprocess.run(
        ["cargo", "build", "--quiet", "--manifest-path", os.path.join(PROJECT_DIR, "Cargo.toml")],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert build.returncode == 0, f"The Rust project did not build successfully:\n{build.stdout}"

    try:
        # First prove that the executable itself produces the required original result.
        run_analyzer(json.loads(original_input.decode("utf-8")))

        # Then use unpredictable identifiers and ordering so a hardcoded report cannot pass.
        ids = [f"TX_{secrets.token_hex(6)}" for _ in range(11)]
        events = []

        # Eight transactions form one directed cycle.
        for i in range(8):
            events.append({"tx_id": ids[i], "waits_for": ids[(i + 1) % 8]})

        # Give cycle members differing out-degrees, including alphabetical tie-breaks.
        events.extend([
            {"tx_id": ids[0], "waits_for": ids[2]},
            {"tx_id": ids[0], "waits_for": ids[3]},
            {"tx_id": ids[1], "waits_for": ids[4]},
            {"tx_id": ids[2], "waits_for": ids[5]},
            {"tx_id": ids[3], "waits_for": ids[6]},
        ])

        # This acyclic transaction has a high out-degree and must be filtered out.
        for target in ids[:7]:
            events.append({"tx_id": ids[8], "waits_for": target})
        events.append({"tx_id": ids[9], "waits_for": ids[10]})

        random.SystemRandom().shuffle(events)
        run_analyzer(events)

        # Exercise self-loops and several separate strongly connected components.
        ids2 = [f"NODE_{secrets.token_hex(6)}" for _ in range(9)]
        events2 = [
            {"tx_id": ids2[0], "waits_for": ids2[0]},
            {"tx_id": ids2[0], "waits_for": ids2[8]},
            {"tx_id": ids2[1], "waits_for": ids2[2]},
            {"tx_id": ids2[2], "waits_for": ids2[1]},
            {"tx_id": ids2[1], "waits_for": ids2[8]},
            {"tx_id": ids2[3], "waits_for": ids2[4]},
            {"tx_id": ids2[4], "waits_for": ids2[5]},
            {"tx_id": ids2[5], "waits_for": ids2[3]},
            {"tx_id": ids2[6], "waits_for": ids2[7]},
            {"tx_id": ids2[7], "waits_for": ids2[8]},
        ]
        random.SystemRandom().shuffle(events2)
        run_analyzer(events2)
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original_input)


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
