#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import uuid
from pathlib import Path

PROJECT = Path("/home/user/deadlock_detector")
MANIFEST = PROJECT / "Cargo.toml"
MAIN_RS = PROJECT / "src" / "main.rs"
CSV_PATH = Path("/home/user/wait_for_graph.csv")
REPORT_PATH = Path("/home/user/deadlock_report.json")

ORIGINAL_CSV = """waiting_txn,holding_txn
TXN-105,TXN-209
TXN-209,TXN-314
TXN-314,TXN-881
TXN-881,TXN-402
TXN-402,TXN-550
TXN-550,TXN-209
TXN-600,TXN-105
TXN-700,TXN-600
TXN-402,TXN-999
"""
EXPECTED_ORIGINAL = ["TXN-209", "TXN-314", "TXN-402", "TXN-550", "TXN-881"]


def run_detector():
    if REPORT_PATH.exists():
        REPORT_PATH.unlink()

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    env["CARGO_HOME"] = "/home/user/.cargo"
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", str(MANIFEST)],
        cwd=str(PROJECT),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        "The Rust program failed to run.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


def read_report():
    assert os.path.isfile(REPORT_PATH), f"The output file {REPORT_PATH} was not found."
    try:
        with open(REPORT_PATH, "r") as f:
            actual_data = json.load(f)
    except json.JSONDecodeError:
        assert False, f"The file {REPORT_PATH} does not contain valid JSON."
    except Exception as e:
        assert False, f"Error reading {REPORT_PATH}: {e}"

    assert isinstance(actual_data, list), f"The JSON in {REPORT_PATH} should be an array."
    return actual_data


def test_deadlock_detector_project_and_behavior():
    assert PROJECT.is_dir(), f"The Rust project directory {PROJECT} was not found."
    assert MANIFEST.is_file(), f"The Rust manifest {MANIFEST} was not found."
    assert MAIN_RS.is_file(), f"The Rust source file {MAIN_RS} was not found."
    assert MAIN_RS.stat().st_size > 0, f"The Rust source file {MAIN_RS} is empty."

    # Execute the submitted program on the provided graph and retain the original
    # verifier's exact report assertion.
    CSV_PATH.write_text(ORIGINAL_CSV)
    run_detector()
    actual_data = read_report()
    assert actual_data == EXPECTED_ORIGINAL, (
        "The deadlock report content is incorrect.\n"
        f"Expected: {EXPECTED_ORIGINAL}\n"
        f"Actual:   {actual_data}"
    )

    try:
        # Exercise the program on unpredictable graphs so a prewritten report
        # cannot pass. Each graph has one cycle plus acyclic feeder/branch nodes.
        for _ in range(3):
            tag = uuid.uuid4().hex[:10]
            cycle_len = random.SystemRandom().randint(3, 7)
            cycle = [f"C-{tag}-{i}" for i in range(cycle_len)]
            feeder = [f"F-{tag}-{i}" for i in range(3)]
            branch = [f"B-{tag}-{i}" for i in range(3)]

            edges = []
            for i, node in enumerate(cycle):
                edges.append((node, cycle[(i + 1) % cycle_len]))
            edges.extend([
                (feeder[0], feeder[1]),
                (feeder[1], feeder[2]),
                (feeder[2], cycle[0]),
                (cycle[cycle_len // 2], branch[0]),
                (branch[0], branch[1]),
                (branch[0], branch[2]),
            ])
            random.SystemRandom().shuffle(edges)

            csv_text = "waiting_txn,holding_txn\n" + "".join(
                f"{waiting},{holding}\n" for waiting, holding in edges
            )
            CSV_PATH.write_text(csv_text)
            run_detector()
            actual = read_report()
            expected = sorted(cycle)
            assert actual == expected, (
                "The Rust program produced an incorrect report for a generated graph.\n"
                f"Expected: {expected}\n"
                f"Actual:   {actual}"
            )
    finally:
        # Restore the task's supplied input and output as the final state.
        CSV_PATH.write_text(ORIGINAL_CSV)
        run_detector()

    restored = read_report()
    assert restored == EXPECTED_ORIGINAL, (
        "The deadlock report content is incorrect after restoring the supplied graph.\n"
        f"Expected: {EXPECTED_ORIGINAL}\n"
        f"Actual:   {restored}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
