#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import struct
import subprocess
import tempfile
from pathlib import Path

OUTPUT_PATH = Path("/home/user/recovery.cypher")
BACKUP_PATH = Path("/app/graph_backup.bin")


def test_recovery_cypher_metric():
    expected_source = 8374
    expected_targets = {1020, 45, 9991}
    output_path = "/home/user/recovery.cypher"

    assert os.path.exists(output_path), f"Output file not found: {output_path}"

    with open(output_path, "r") as f:
        content = f.read()

    # Parse output, allowing for optional spaces after the colon
    pattern = r"CREATE \(n:Node \{id:\s*(\d+)\}\)-\[:CONNECTED_TO\]->\(m:Node \{id:\s*(\d+)\}\);"
    matches = re.findall(pattern, content)

    actual_targets = set()
    valid_source_count = 0

    for src, tgt in matches:
        if int(src) == expected_source:
            actual_targets.add(int(tgt))
            valid_source_count += 1

    assert valid_source_count > 0, f"No valid Cypher statements found for the expected source node ID ({expected_source}) in {output_path}."

    true_positives = len(actual_targets.intersection(expected_targets))
    false_positives = len(actual_targets - expected_targets)
    false_negatives = len(expected_targets - actual_targets)

    precision = true_positives / (true_positives + false_positives) if (true_positives + false_positives) > 0 else 0.0
    recall = true_positives / (true_positives + false_negatives) if (true_positives + false_negatives) > 0 else 0.0

    if precision + recall == 0:
        f1_score = 0.0
    else:
        f1_score = 2 * (precision * recall) / (precision + recall)

    assert f1_score >= 1.0, (
        f"F1 score {f1_score:.2f} is below the required threshold of 1.0.\n"
        f"Expected targets for node {expected_source}: {expected_targets}\n"
        f"Actual valid targets found: {actual_targets}"
    )


def assert_dynamic_output(expected_source, expected_targets):
    assert OUTPUT_PATH.exists(), "The compiled C program did not create /home/user/recovery.cypher"
    content = OUTPUT_PATH.read_text()
    pattern = r"CREATE \(n:Node \{id:\s*(\d+)\}\)-\[:CONNECTED_TO\]->\(m:Node \{id:\s*(\d+)\}\);"
    matches = re.findall(pattern, content)
    actual_targets = {int(tgt) for src, tgt in matches if int(src) == expected_source}
    valid_source_count = sum(1 for src, _ in matches if int(src) == expected_source)
    assert valid_source_count > 0, "No valid Cypher statements were produced by the compiled C program"
    assert actual_targets == expected_targets, (
        f"The compiled C program did not parse the test binary correctly: "
        f"expected {expected_targets}, got {actual_targets}"
    )


def test_c_program_executes_and_parses_binary():
    search_roots = [Path("/home/user"), Path("/app")]
    sources = []
    for root in search_roots:
        if root.exists():
            sources.extend(p for p in root.rglob("*.c") if p.is_file())
    assert sources, "No C source program was found under /home/user or /app"

    original_backup = BACKUP_PATH.read_bytes()
    original_output = OUTPUT_PATH.read_bytes() if OUTPUT_PATH.exists() else None
    failures = []

    try:
        for source in sorted(set(sources)):
            try:
                with tempfile.TemporaryDirectory() as td:
                    executable = Path(td) / "recover"
                    subprocess.run(
                        ["gcc", "-std=c11", "-O2", str(source), "-o", str(executable)],
                        check=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        timeout=20,
                    )

                    # Execute the submitted program against the real artifact, rather
                    # than trusting a recovery.cypher file that was written directly.
                    BACKUP_PATH.write_bytes(original_backup)
                    OUTPUT_PATH.unlink(missing_ok=True)
                    subprocess.run(
                        [str(executable)],
                        cwd=str(source.parent),
                        check=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        timeout=10,
                    )
                    test_recovery_cypher_metric()

                    # Replace the dump temporarily with a fresh instance whose edge
                    # values are chosen by the verifier. This rejects a program that
                    # merely prints the three known answers instead of parsing records.
                    dynamic_targets = set()
                    while len(dynamic_targets) < 4:
                        value = secrets.randbelow(2**32)
                        if value not in {8374, 1020, 45, 9991}:
                            dynamic_targets.add(value)
                    ordered_targets = list(dynamic_targets)
                    blob = bytearray()
                    blob += struct.pack("<IIII", 314159, 2, 2718, 1618)
                    blob += struct.pack("<II", 8374, len(ordered_targets))
                    blob += struct.pack("<" + "I" * len(ordered_targets), *ordered_targets)
                    blob += struct.pack("<III", 424242, 1, 777777)
                    BACKUP_PATH.write_bytes(blob)
                    OUTPUT_PATH.unlink(missing_ok=True)
                    subprocess.run(
                        [str(executable)],
                        cwd=str(source.parent),
                        check=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        timeout=10,
                    )
                    assert_dynamic_output(8374, dynamic_targets)
                    return
            except Exception as exc:
                failures.append(f"{source}: {exc}")
            finally:
                BACKUP_PATH.write_bytes(original_backup)
                if original_output is None:
                    OUTPUT_PATH.unlink(missing_ok=True)
                else:
                    OUTPUT_PATH.write_bytes(original_output)
    finally:
        BACKUP_PATH.write_bytes(original_backup)
        if original_output is None:
            OUTPUT_PATH.unlink(missing_ok=True)
        else:
            OUTPUT_PATH.write_bytes(original_output)

    raise AssertionError("No submitted C program compiled and passed execution tests:\n" + "\n".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
