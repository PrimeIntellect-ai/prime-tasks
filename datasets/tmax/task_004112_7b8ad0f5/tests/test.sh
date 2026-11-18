#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
from pathlib import Path

import pytest


def test_clean_graph_go_exists():
    """Check that the student's Go program exists."""
    file_path = "/home/user/clean_graph.go"
    assert os.path.exists(file_path), f"Student file {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."


def test_clean_backup_exists_and_correct():
    """Check that the output file exists and has the correct sorted content."""
    file_path = "/home/user/clean_backup.csv"
    assert os.path.exists(file_path), f"Output file {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

    expected_lines = [
        "nodeA,current_status,ACTIVE,100",
        "nodeB,current_status,INACTIVE,200",
        "nodeC,current_status,ERROR,400",
        "user1,manages,nodeA,10",
        "user4,manages,nodeA,12"
    ]

    with open(file_path, "r") as f:
        actual_content = f.read().strip()

    actual_lines = [line.strip() for line in actual_content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"Content of {file_path} does not match the expected final state. "
        f"Expected:\n{chr(10).join(expected_lines)}\nActual:\n{chr(10).join(actual_lines)}"
    )


def derive_expected(lines):
    latest = {}
    parsed = []
    for line in lines:
        subject, predicate, obj, timestamp_text = line.split(",")
        timestamp = int(timestamp_text)
        parsed.append((line, subject, predicate, obj, timestamp))
        if predicate == "current_status":
            previous = latest.get(subject)
            if previous is None or timestamp > previous[0]:
                latest[subject] = (timestamp, line, obj)

    projected = [entry[1] for entry in latest.values()]
    for line, _subject, predicate, obj, _timestamp in parsed:
        if predicate == "manages" and obj in latest and latest[obj][2] == "ACTIVE":
            projected.append(line)
    return sorted(projected)


def test_go_program_processes_unseen_input():
    source = Path("/home/user/clean_graph.go")
    input_path = Path("/home/user/graph_backup.csv")
    output_path = Path("/home/user/clean_backup.csv")

    original_input = input_path.read_bytes()
    original_output = output_path.read_bytes()

    try:
        for case_number in range(2):
            token = secrets.token_hex(8)
            lines = []

            for i in range(16):
                node = f"n_{token}_{case_number}_{i:02d}"
                base = 1000 + case_number * 500 + i * 20
                mode = i % 4
                if mode == 0:
                    lines.extend([
                        f"{node},current_status,INACTIVE,{base + 1}",
                        f"{node},current_status,PENDING,{base + 5}",
                        f"{node},current_status,ACTIVE,{base + 12}",
                    ])
                elif mode == 1:
                    lines.extend([
                        f"{node},current_status,ACTIVE,{base + 2}",
                        f"{node},current_status,ERROR,{base + 15}",
                    ])
                elif mode == 2:
                    lines.append(f"{node},current_status,ACTIVE,{base + 7}")
                # mode 3 deliberately has no current_status edge.

                lines.append(f"owner_{token}_{i},manages,{node},{50 + i}")
                lines.append(f"owner_{token}_{i},observes,{node},{70 + i}")

            lines.extend([
                f"orphan_{token},manages,missing_{token},900",
                f"misc_{token},related_to,n_{token}_{case_number}_00,901",
            ])
            random.SystemRandom().shuffle(lines)
            expected = derive_expected(lines)

            input_path.write_text("\n".join(lines) + "\n")
            if output_path.exists():
                output_path.unlink()

            result = subprocess.run(
                ["go", "run", str(source)],
                cwd="/home/user",
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
            assert result.returncode == 0, (
                f"Go program failed on unseen input with exit code {result.returncode}. "
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
            assert output_path.exists() and output_path.is_file(), (
                "Go program did not create /home/user/clean_backup.csv"
            )

            actual = output_path.read_text().splitlines()
            assert actual == expected, (
                "Go program produced an incorrect projection for unseen input. "
                f"Expected:\n{chr(10).join(expected)}\nActual:\n{chr(10).join(actual)}"
            )
    finally:
        input_path.write_bytes(original_input)
        output_path.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
