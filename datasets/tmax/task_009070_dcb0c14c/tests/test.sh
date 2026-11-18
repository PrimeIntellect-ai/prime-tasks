#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

import pytest

CALC_DIR = "/home/user/uptime_calculator"
MAIN_PATH = os.path.join(CALC_DIR, "main.go")
PINGS_PATH = os.path.join(CALC_DIR, "pings.jsonl")
REPORT_PATH = "/home/user/uptime_report.json"


def write_pings(rows):
    with open(PINGS_PATH, "w", encoding="utf-8") as f:
        for timestamp, up in rows:
            f.write(json.dumps({"timestamp": timestamp, "up": up}, separators=(",", ":")) + "\n")


def run_program():
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    result = subprocess.run(
        ["go", "run", "main.go"],
        cwd=CALC_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        "Running main.go failed.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), (
        f"File {REPORT_PATH} does not exist. Did you run the fixed Go program?"
    )

    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"File {REPORT_PATH} does not contain valid JSON: {exc}")

    assert set(data) == {"longest_downtime_minutes", "uptime_percentage"}, (
        "The report must contain exactly the required two keys."
    )
    return data


def expected_values(rows):
    longest = 0
    current = 0
    for _, up in rows:
        if not up:
            current += 1
            longest = max(longest, current)
        else:
            current = 0

    selected = [up for timestamp, up in rows if 100 <= timestamp <= 200]
    percentage = float(f"{(sum(selected) / len(selected)) * 100:.2f}")
    return longest, percentage


def test_main_go_bugs_fixed_and_program_behaviour():
    assert os.path.isfile(MAIN_PATH), "main.go not found."
    assert os.path.isfile(PINGS_PATH), "pings.jsonl not found."

    with open(MAIN_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "i <= len(pings)" not in content, (
        "Bug 1 (off-by-one boundary error) is still present in main.go"
    )
    assert "p.Timestamp < endTS" not in content, (
        "Bug 2 (exclusive boundary condition) is still present in main.go"
    )

    with open(PINGS_PATH, "rb") as f:
        original_pings = f.read()

    try:
        # Exercise the submitted Go program on a verifier-generated dataset.
        # The final timestamp is up, so excluding endTS produces a detectably
        # different percentage. The random placement prevents a hardcoded report.
        rng = secrets.SystemRandom()
        up_count_before_end = rng.randint(25, 75)
        up_indices = set(rng.sample(range(100), up_count_before_end))
        generated_rows = [
            (100 + i, i in up_indices) for i in range(100)
        ] + [(200, True)]
        write_pings(generated_rows)

        generated_report = run_program()
        expected_longest, expected_pct = expected_values(generated_rows)
        assert generated_report["longest_downtime_minutes"] == expected_longest, (
            "main.go calculated the wrong longest contiguous downtime for "
            "the verifier-generated input."
        )
        assert abs(generated_report["uptime_percentage"] - expected_pct) < 0.01, (
            "main.go calculated the wrong inclusive-window uptime percentage "
            "for the verifier-generated input."
        )

        # Run against the task's canonical dataset and preserve the original
        # report-content assertions.
        canonical_rows = [
            (timestamp, not (140 <= timestamp <= 154))
            for timestamp in range(100, 201)
        ]
        write_pings(canonical_rows)
        data = run_program()

        assert "longest_downtime_minutes" in data, (
            "Key 'longest_downtime_minutes' missing from JSON."
        )
        assert "uptime_percentage" in data, (
            "Key 'uptime_percentage' missing from JSON."
        )
        assert data["longest_downtime_minutes"] == 15, (
            "Expected longest_downtime_minutes to be 15, got "
            f"{data['longest_downtime_minutes']}"
        )
        actual_pct = data["uptime_percentage"]
        assert abs(actual_pct - 85.15) < 0.01, (
            f"Expected uptime_percentage to be 85.15, got {actual_pct}"
        )
    finally:
        with open(PINGS_PATH, "wb") as f:
            f.write(original_pings)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
