#!/bin/bash
set -e
mkdir -p /logs/verifier

cp -a /home/user/backup_metadata.db /tmp/original_backup_metadata.db
if [ -f /home/user/anomalies.json ]; then
    cp -a /home/user/anomalies.json /tmp/original_anomalies.json
    HAD_ANOMALIES=1
else
    HAD_ANOMALIES=0
fi

restore_state() {
    cp -a /tmp/original_backup_metadata.db /home/user/backup_metadata.db
    if [ "$HAD_ANOMALIES" = "1" ]; then
        cp -a /tmp/original_anomalies.json /home/user/anomalies.json
    else
        rm -f /home/user/anomalies.json
    fi
    rm -f /home/user/backup_metadata.db-wal /home/user/backup_metadata.db-shm
}
trap restore_state EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
from pathlib import Path
import pwd
import secrets
import sqlite3
import subprocess

import pytest

ANOMALIES_FILE = "/home/user/anomalies.json"
DATABASE_FILE = "/home/user/backup_metadata.db"


def load_report():
    with open(ANOMALIES_FILE, "r") as f:
        return json.load(f)


def validate_strict_schema(data):
    assert isinstance(data, dict), "The root of the JSON must be an object."
    assert set(data) == {"anomalies"}, "The root object may only contain 'anomalies'."
    assert isinstance(data["anomalies"], list), "The 'anomalies' property must be an array."
    required = {"child_backup_id", "parent_backup_id", "chain_root_id"}
    for item in data["anomalies"]:
        assert isinstance(item, dict), "Each item in 'anomalies' must be an object."
        assert set(item) == required, "Anomaly items must contain exactly the three schema properties."
        for key in required:
            assert isinstance(item[key], str), f"The value for '{key}' must be a string."


def test_anomalies_file_exists():
    assert os.path.isfile(ANOMALIES_FILE), f"The file {ANOMALIES_FILE} does not exist."


def test_anomalies_json_format():
    with open(ANOMALIES_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {ANOMALIES_FILE} is not valid JSON.")

    assert isinstance(data, dict), "The root of the JSON must be an object."
    assert "anomalies" in data, "The JSON object must contain the 'anomalies' key."
    assert isinstance(data["anomalies"], list), "The 'anomalies' property must be an array."
    for item in data["anomalies"]:
        assert isinstance(item, dict), "Each item in 'anomalies' must be an object."
        for req_key in ["child_backup_id", "parent_backup_id", "chain_root_id"]:
            assert req_key in item, f"Missing required key '{req_key}' in anomaly item."
            assert isinstance(item[req_key], str), f"The value for '{req_key}' must be a string."

    validate_strict_schema(data)


def test_anomalies_content():
    data = load_report()
    expected_anomalies = [
        {"child_backup_id": "B3", "parent_backup_id": "B2", "chain_root_id": "B1"},
        {"child_backup_id": "D2", "parent_backup_id": "D1", "chain_root_id": "D1"},
    ]
    actual_anomalies = data.get("anomalies", [])
    assert len(actual_anomalies) == len(expected_anomalies), (
        f"Expected {len(expected_anomalies)} anomalies, but found {len(actual_anomalies)}."
    )
    sorted_actual = sorted(actual_anomalies, key=lambda x: x.get("child_backup_id", ""))
    sorted_expected = sorted(expected_anomalies, key=lambda x: x["child_backup_id"])
    assert sorted_actual == sorted_expected, "The anomalies reported do not match the expected anomalies."


def find_scripts():
    excluded = {
        Path(DATABASE_FILE).resolve(),
        Path(ANOMALIES_FILE).resolve(),
    }
    recognized = {".py", ".sh", ".sql", ".pl", ".rb", ".js"}
    candidates = []
    for path in Path("/home/user").rglob("*"):
        if not path.is_file() or path.resolve() in excluded:
            continue
        try:
            with path.open("rb") as f:
                first = f.readline(512)
        except OSError:
            continue
        if path.suffix.lower() in recognized or first.startswith(b"#!"):
            candidates.append(path)
    return sorted(candidates, key=lambda p: str(p))


def command_for(path):
    suffix = path.suffix.lower()
    if suffix == ".py":
        return ["python3", str(path)], None
    if suffix == ".sh":
        return ["bash", str(path)], None
    if suffix == ".sql":
        return ["sqlite3", DATABASE_FILE], path.read_bytes()

    first = path.read_text(errors="ignore").splitlines()[0] if path.stat().st_size else ""
    if "python" in first:
        return ["python3", str(path)], None
    if any(shell in first for shell in ("/sh", "bash", "dash")):
        return ["bash", str(path)], None
    if os.access(path, os.X_OK):
        return [str(path)], None
    return None, None


def create_database(backups, storage):
    for suffix in ("", "-wal", "-shm"):
        try:
            os.unlink(DATABASE_FILE + suffix)
        except FileNotFoundError:
            pass
    con = sqlite3.connect(DATABASE_FILE)
    con.executescript("""
        CREATE TABLE backups (id TEXT PRIMARY KEY, parent_id TEXT, status TEXT);
        CREATE TABLE storage (backup_id TEXT PRIMARY KEY, tier TEXT);
    """)
    con.executemany("INSERT INTO backups VALUES (?, ?, ?)", backups)
    con.executemany("INSERT INTO storage VALUES (?, ?)", storage)
    con.commit()
    con.close()
    os.chmod(DATABASE_FILE, 0o666)


def derive_expected(backups, storage):
    nodes = {backup_id: (parent_id, status) for backup_id, parent_id, status in backups}
    tiers = dict(storage)
    result = []
    for child_id, parent_id, child_status in backups:
        if parent_id is None or child_status != "success" or parent_id not in nodes:
            continue
        if nodes[parent_id][1] != "success":
            continue
        if tiers.get(child_id) != "hot" or tiers.get(parent_id) != "cold":
            continue

        root = child_id
        seen = set()
        while root in nodes and nodes[root][0] is not None and root not in seen:
            seen.add(root)
            root = nodes[root][0]
        result.append({
            "child_backup_id": child_id,
            "parent_backup_id": parent_id,
            "chain_root_id": root,
        })
    return sorted(result, key=lambda item: (item["child_backup_id"], item["parent_backup_id"], item["chain_root_id"]))


def run_candidate(path):
    command, stdin_data = command_for(path)
    if command is None:
        return False, "unsupported script type"

    user = pwd.getpwnam("user")
    env = os.environ.copy()
    env["HOME"] = "/home/user"
    env["USER"] = "user"

    def demote():
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    try:
        completed = subprocess.run(
            command,
            input=stdin_data,
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
            preexec_fn=demote,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, str(exc)
    if completed.returncode != 0:
        return False, completed.stderr.decode(errors="replace")[-500:]
    return True, ""


def test_reusable_script_on_generated_databases():
    candidates = find_scripts()
    assert candidates, "No analysis script was found under /home/user."

    prefix = "V" + secrets.token_hex(6)
    fixtures = [
        (
            [
                (prefix + "R1", None, "success"),
                (prefix + "M1", prefix + "R1", "success"),
                (prefix + "C1", prefix + "M1", "success"),
                (prefix + "R2", None, "success"),
                (prefix + "C2", prefix + "R2", "success"),
                (prefix + "N1", prefix + "C2", "success"),
            ],
            [
                (prefix + "R1", "warm"),
                (prefix + "M1", "cold"),
                (prefix + "C1", "hot"),
                (prefix + "R2", "cold"),
                (prefix + "C2", "hot"),
                (prefix + "N1", "warm"),
            ],
        ),
        (
            [
                (prefix + "X1", None, "success"),
                (prefix + "X2", prefix + "X1", "failed"),
                (prefix + "X3", prefix + "X1", "running"),
                (prefix + "Y1", None, "failed"),
                (prefix + "Y2", prefix + "Y1", "success"),
                (prefix + "Z1", None, "success"),
                (prefix + "Z2", prefix + "Z1", "success"),
            ],
            [
                (prefix + "X1", "cold"),
                (prefix + "X2", "hot"),
                (prefix + "X3", "hot"),
                (prefix + "Y1", "cold"),
                (prefix + "Y2", "hot"),
                (prefix + "Z1", "warm"),
                (prefix + "Z2", "hot"),
            ],
        ),
    ]

    failures = []
    for candidate in candidates:
        passed_all = True
        reason = ""
        for backups, storage in fixtures:
            create_database(backups, storage)
            try:
                os.unlink(ANOMALIES_FILE)
            except FileNotFoundError:
                pass

            ok, reason = run_candidate(candidate)
            if not ok:
                passed_all = False
                break
            try:
                data = load_report()
                validate_strict_schema(data)
                actual = sorted(
                    data["anomalies"],
                    key=lambda item: (item["child_backup_id"], item["parent_backup_id"], item["chain_root_id"]),
                )
                expected = derive_expected(backups, storage)
                assert actual == expected
            except Exception as exc:
                passed_all = False
                reason = str(exc)
                break

        if passed_all:
            return
        failures.append(f"{candidate}: {reason}")

    pytest.fail("No submitted script produced correct reports for generated databases. " + " | ".join(failures))
TEST_EOF

status=0
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 || status=$?
restore_state
trap - EXIT

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
