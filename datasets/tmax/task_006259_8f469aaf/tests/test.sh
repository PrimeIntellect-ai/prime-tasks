#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import shutil
import stat
import subprocess
from collections import Counter, defaultdict
from pathlib import Path

SCRIPT = Path("/home/user/pipeline.sh")
DATA_DIR = Path("/home/user/data")
OUTPUT_DIR = Path("/home/user/output")
USERS = DATA_DIR / "users.csv"
LOGS = DATA_DIR / "access_logs.csv"
HEADER = ["timestamp", "ip", "user_id", "role", "region", "endpoint", "status"]


def derive_expected():
    with USERS.open(newline="") as f:
        users_reader = csv.DictReader(f)
        assert users_reader.fieldnames == ["user_id", "role", "region"]
        users = {row["user_id"]: row for row in users_reader}

    normalized = []
    with LOGS.open(newline="") as f:
        logs_reader = csv.DictReader(f)
        assert logs_reader.fieldnames == ["timestamp", "ip", "user_id", "endpoint", "status"]
        for row in logs_reader:
            assert row["user_id"] in users, f"Unknown user_id in input: {row['user_id']}"
            user = users[row["user_id"]]
            normalized.append([
                row["timestamp"],
                row["ip"],
                row["user_id"],
                user["role"],
                user["region"],
                row["endpoint"].split("?", 1)[0].lower(),
                row["status"],
            ])

    normalized.sort(key=lambda row: row[0])

    by_role = defaultdict(list)
    for row in normalized:
        by_role[row[3]].append(row)
    sample = []
    for role in sorted(by_role):
        sample.extend(by_role[role][:2])
    sample.sort(key=lambda row: (row[3], row[0]))

    anomalies = Counter()
    for row in normalized:
        if row[5].startswith("/api/v2/") and int(row[6]) >= 400:
            anomalies[row[2]] += 1
    assert anomalies, "Test input must contain at least one anomaly"
    highest = max(anomalies.values())
    tied = [uid for uid, count in anomalies.items() if count == highest]
    try:
        anomaly_user = min(tied, key=int)
    except ValueError:
        anomaly_user = min(tied)

    return normalized, sample, anomaly_user


def run_pipeline():
    if OUTPUT_DIR.exists():
        shutil.rmtree(OUTPUT_DIR)
    result = subprocess.run(
        [str(SCRIPT)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"pipeline.sh exited with status {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_csv(path):
    assert path.is_file(), f"File {path} does not exist."
    with path.open("r", newline="") as f:
        return list(csv.reader(f))


def check_outputs(expected_normalized, expected_sample, expected_anomaly, canonical=False):
    assert OUTPUT_DIR.is_dir(), "Directory /home/user/output/ does not exist. The script should create it."

    normalized_path = OUTPUT_DIR / "normalized_joined.csv"
    normalized_rows = read_csv(normalized_path)
    assert len(normalized_rows) > 1, f"{normalized_path} is empty or missing data rows."
    assert normalized_rows[0] == HEADER, (
        f"{normalized_path} header is incorrect. Expected {HEADER}, got {normalized_rows[0]}."
    )
    data_rows = normalized_rows[1:]
    assert all(len(row) == len(HEADER) for row in data_rows), "Malformed normalized CSV row."
    timestamps = [row[0] for row in data_rows]
    assert timestamps == sorted(timestamps), f"{normalized_path} is not sorted chronologically by timestamp."
    for i, row in enumerate(data_rows):
        assert "?" not in row[5], f"Row {i+1} contains query parameters: {row[5]}"
        assert row[5] == row[5].lower(), f"Row {i+1} contains uppercase endpoint characters: {row[5]}"
        if row[2] == "101":
            assert row[3] == "admin", f"Join failed for user 101: expected admin, got {row[3]}."
    assert data_rows == expected_normalized, (
        "normalized_joined.csv does not exactly match the input-derived, normalized chronological join."
    )

    sample_path = OUTPUT_DIR / "stratified_sample.csv"
    sample_rows = read_csv(sample_path)
    assert len(sample_rows) > 1, f"{sample_path} is empty or missing data rows."
    assert sample_rows[0] == HEADER, (
        f"{sample_path} header is incorrect. Expected {HEADER}, got {sample_rows[0]}."
    )
    sample_data = sample_rows[1:]
    assert all(len(row) == len(HEADER) for row in sample_data), "Malformed sample CSV row."
    roles_timestamps = [(row[3], row[0]) for row in sample_data]
    assert roles_timestamps == sorted(roles_timestamps), (
        f"{sample_path} is not sorted by role and then timestamp."
    )
    role_counts = Counter(row[3] for row in sample_data)
    for role, count in role_counts.items():
        assert count <= 2, f"Role {role!r} has more than 2 entries ({count})."
    if canonical:
        assert set(role_counts) == {"admin", "bot", "guest", "user"}, (
            f"Expected canonical roles admin, bot, guest, user; found {set(role_counts)}."
        )
    assert sample_data == expected_sample, (
        "stratified_sample.csv is not exactly the first two chronological rows for every role."
    )
    expected_counts = Counter(row[3] for row in expected_sample)
    assert role_counts == expected_counts, "The sample does not contain exactly two rows per input role."

    anomaly_path = OUTPUT_DIR / "anomaly_user.txt"
    assert anomaly_path.is_file(), f"File {anomaly_path} does not exist."
    content = anomaly_path.read_text().strip()
    assert content == expected_anomaly, (
        f"Incorrect anomaly user. Expected input-derived value {expected_anomaly!r}, got {content!r}."
    )
    if canonical:
        assert content == "105", f"Incorrect canonical anomaly user: expected '105', got {content!r}."


def test_pipeline_end_to_end_and_on_derived_input():
    assert SCRIPT.exists(), "/home/user/pipeline.sh does not exist."
    assert not SCRIPT.is_symlink(), "/home/user/pipeline.sh must be an actual script, not a symlink."
    assert stat.S_ISREG(SCRIPT.stat().st_mode), "/home/user/pipeline.sh is not a regular file."
    assert os.access(SCRIPT, os.X_OK), "/home/user/pipeline.sh is not executable."

    original_users = USERS.read_bytes()
    original_logs = LOGS.read_bytes()
    original_expected = derive_expected()

    try:
        run_pipeline()
        check_outputs(*original_expected, canonical=True)

        token = secrets.token_hex(4)
        base = 2000 + secrets.randbelow(5000)
        u1, u2, u3, u4 = [str(base + n) for n in (10, 20, 30, 40)]
        role_a = f"ops_{token}"
        role_b = f"member_{token}"
        role_c = f"bot_{token}"

        USERS.write_text(
            "user_id,role,region\n"
            f"{u1},{role_a},NA\n"
            f"{u2},{role_b},EU\n"
            f"{u3},{role_b},AP\n"
            f"{u4},{role_c},SA\n"
        )
        LOGS.write_text(
            "timestamp,ip,user_id,endpoint,status\n"
            f"2025-02-01T00:05:00,10.0.0.2,{u2},/API/V2/Submit?x=1,500\n"
            f"2025-02-01T00:01:00,10.0.0.1,{u1},/Home?theme=X,200\n"
            f"2025-02-01T00:04:00,10.0.0.4,{u4},/api/v2/crawl,401\n"
            f"2025-02-01T00:02:00,10.0.0.3,{u3},/Api/V2/info?q=Y,404\n"
            f"2025-02-01T00:06:00,10.0.0.4,{u4},/API/v2/crawl?q=2,403\n"
            f"2025-02-01T00:03:00,10.0.0.2,{u2},/api/v1/list?z=3,200\n"
            f"2025-02-01T00:07:00,10.0.0.1,{u1},/API/V2/admin,500\n"
            f"2025-02-01T00:08:00,10.0.0.3,{u3},/api/v2/info,500\n"
        )
        synthetic_expected = derive_expected()
        run_pipeline()
        check_outputs(*synthetic_expected)
    finally:
        USERS.write_bytes(original_users)
        LOGS.write_bytes(original_logs)
        try:
            run_pipeline()
        except Exception:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
