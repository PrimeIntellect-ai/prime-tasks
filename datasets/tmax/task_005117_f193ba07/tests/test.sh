#!/bin/bash
set -e
mkdir -p /logs/verifier

backup_dir=$(mktemp -d)
raw_existed=0
summary_existed=0
if [ -e /home/user/raw_feedback.csv ]; then
    cp -a /home/user/raw_feedback.csv "$backup_dir/raw_feedback.csv"
    raw_existed=1
fi
if [ -e /home/user/summary.json ]; then
    cp -a /home/user/summary.json "$backup_dir/summary.json"
    summary_existed=1
fi
restore_files() {
    if [ "$raw_existed" -eq 1 ]; then
        rm -rf /home/user/raw_feedback.csv
        cp -a "$backup_dir/raw_feedback.csv" /home/user/raw_feedback.csv
    else
        rm -rf /home/user/raw_feedback.csv
    fi
    if [ "$summary_existed" -eq 1 ]; then
        rm -rf /home/user/summary.json
        cp -a "$backup_dir/summary.json" /home/user/summary.json
    else
        rm -rf /home/user/summary.json
    fi
    rm -rf "$backup_dir"
}
trap restore_files EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import re
import secrets
import subprocess

import pytest

SCRIPT = "/home/user/process_feedback.py"
RAW = "/home/user/raw_feedback.csv"
SUMMARY = "/home/user/summary.json"
EXPECTED_KEYS = {
    "total_valid_rows",
    "average_rating",
    "region_counts",
    "total_non_ascii_alnum",
}

ORIGINAL_ROWS = [
    ("001", "2023-10-15T14:30:00Z", "IP: 192.168.1.1 | Region: EU | browser: chrome", "Привет [RATING: 5]"),
    ("002", "2023-10-15 14:30:00", "IP: 10.0.0.1 | Region: NA", "Good [RATING: 4]"),
    ("003", "2023-10-16T09:15:00Z", "Some garbage here. Region: NA. User IP: 10.0.0.1.", "Excellent [RATING:4] 漢字"),
    ("004", "2023-10-17T11:00:00Z", "IP: 256.0.0.1 | Region: EU", "Bad [RATING: 1]"),
    ("005", "2023-10-18T18:45:00Z", "IP: 172.16.0.5 | Region: EU", "Trés bien [RATING: 2]"),
    ("006", "2023-10-19T12:00:00Z", "IP: 8.8.8.8 | Region: AS", "No rating given here"),
    ("007", "2023-10-19T13:00:00Z", "IP: 8.8.8.8 | Region: AS", "Fake rating [RATING: 6]"),
    ("008", "2023-10-20T08:00:00Z", "Just IP: 1.1.1.1 here", "Bad 😭 [RATING: 1]"),
]


def write_csv(rows):
    with open(RAW, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "timestamp", "user_metadata", "feedback_text"])
        writer.writerows(rows)


def run_submission(rows):
    write_csv(rows)
    if os.path.lexists(SUMMARY):
        if os.path.isdir(SUMMARY) and not os.path.islink(SUMMARY):
            import shutil
            shutil.rmtree(SUMMARY)
        else:
            os.unlink(SUMMARY)
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process_feedback.py exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(SUMMARY), "Running process_feedback.py did not create summary.json"
    assert os.path.isfile(SUMMARY), f"{SUMMARY} is not a file"
    with open(SUMMARY, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {SUMMARY} as JSON: {e}")


def valid_ipv4(metadata):
    pattern = re.compile(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])")
    for candidate in pattern.findall(metadata):
        if all(0 <= int(part) <= 255 for part in candidate.split(".")):
            return True
    return False


def reference_summary(rows):
    valid = []
    for _, timestamp, metadata, feedback in rows:
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", timestamp) is None:
            continue
        if not valid_ipv4(metadata):
            continue
        rating_match = re.search(r"\[RATING: ?([1-5])\]", feedback)
        if rating_match is None:
            continue
        region_match = re.search(r"Region: ([A-Za-z]{2})(?![A-Za-z])", metadata)
        region = region_match.group(1) if region_match else "UNKNOWN"
        valid.append((int(rating_match.group(1)), region, feedback))

    region_counts = {}
    for _, region, _ in valid:
        region_counts[region] = region_counts.get(region, 0) + 1
    return {
        "total_valid_rows": len(valid),
        "average_rating": round(sum(r for r, _, _ in valid) / len(valid), 2),
        "region_counts": region_counts,
        "total_non_ascii_alnum": sum(
            1
            for _, _, feedback in valid
            for char in feedback
            if ord(char) > 127 and char.isalnum()
        ),
    }


def make_random_rows():
    rng = random.Random(secrets.randbits(128))
    regions = ["EU", "NA", "AS", None, "EU", "AF", rng.choice(["SA", "OC"])]
    payloads = ["Привет", "漢字", "é", "١٢", "🙂", "a\u0301", "Ångström"]
    rows = []
    for index in range(7):
        rating = rng.randint(1, 5)
        if index == 0:
            ip = "0.0.0.0"
        elif index == 1:
            ip = "255.255.255.255"
        else:
            ip = ".".join(str(rng.randint(0, 255)) for _ in range(4))
        region_text = f" | Region: {regions[index]}" if regions[index] else ""
        metadata = f"noise User IP: {ip}{region_text} tail"
        spacing = " " if index % 2 == 0 else ""
        feedback = f"{payloads[index]} sample [RATING:{spacing}{rating}]"
        rows.append((f"v-{secrets.token_hex(4)}", f"2024-0{index + 1}-1{index}T0{index}:2{index}:3{index}Z", metadata, feedback))

    rows.extend([
        (f"x-{secrets.token_hex(4)}", "2024-01-01 00:00:00", "IP: 1.2.3.4 | Region: EU", "bad timestamp [RATING: 5] é"),
        (f"x-{secrets.token_hex(4)}", "2024-01-01T00:00:00Z", "IP: 999.1.2.3 | Region: NA", "bad ip [RATING: 4] 漢"),
        (f"x-{secrets.token_hex(4)}", "2024-01-01T00:00:00Z", "IP: 8.8.8.8 | Region: AS", "out of range [RATING: 6] Ж"),
        (f"x-{secrets.token_hex(4)}", "2024-01-01T00:00:00Z", "IP: 9.9.9.9", "missing rating Ω"),
    ])
    rng.shuffle(rows)
    return rows


def test_script_exists_and_original_summary_content():
    assert os.path.exists(SCRIPT), f"File {SCRIPT} is missing."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."

    data = run_submission(ORIGINAL_ROWS)

    assert os.path.exists(SUMMARY), f"File {SUMMARY} is missing."
    assert os.path.isfile(SUMMARY), f"{SUMMARY} is not a file."
    assert set(data.keys()) == EXPECTED_KEYS, (
        f"JSON keys mismatch. Expected {EXPECTED_KEYS}, got {set(data.keys())}."
    )
    assert data["total_valid_rows"] == 4, (
        f"Expected total_valid_rows to be 4, got {data['total_valid_rows']}."
    )
    avg_rating = data["average_rating"]
    assert isinstance(avg_rating, (int, float)), (
        f"average_rating must be a number, got {type(avg_rating)}."
    )
    assert math.isclose(avg_rating, 3.0, rel_tol=1e-9), (
        f"Expected average_rating to be 3.0, got {avg_rating}."
    )
    expected_region_counts = {"EU": 2, "NA": 1, "UNKNOWN": 1}
    assert data["region_counts"] == expected_region_counts, (
        f"Expected region_counts to be {expected_region_counts}, got {data['region_counts']}."
    )
    assert data["total_non_ascii_alnum"] == 9, (
        f"Expected total_non_ascii_alnum to be 9, got {data['total_non_ascii_alnum']}."
    )


def test_processes_changed_inputs_instead_of_emitting_constants():
    for _ in range(2):
        rows = make_random_rows()
        expected = reference_summary(rows)
        actual = run_submission(rows)
        assert set(actual.keys()) == EXPECTED_KEYS
        assert actual == expected, f"Expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
