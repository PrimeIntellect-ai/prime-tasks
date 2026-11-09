#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shlex
import shutil
import sqlite3
import subprocess
import tempfile
from pathlib import Path

import pytest


def test_audit_report_content():
    report_path = "/home/user/audit_report.json"
    assert os.path.isfile(report_path), f"Audit report not found at {report_path}"

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File at {report_path} is not valid JSON.")

    expected_data = {
        "employee_id": "E-7734",
        "name": "Jordan Cole",
        "department_name": "Equities",
        "risk_level": 4,
        "total_trade_volume": 1450000.50,
        "number_of_flagged_trades": 3
    }

    # Check types and values
    assert data.get("employee_id") == expected_data["employee_id"], "Incorrect employee_id"
    assert data.get("name") == expected_data["name"], "Incorrect name"
    assert data.get("department_name") == expected_data["department_name"], "Incorrect department_name"
    assert data.get("risk_level") == expected_data["risk_level"], "Incorrect risk_level"
    assert data.get("total_trade_volume") == expected_data["total_trade_volume"], "Incorrect total_trade_volume"
    assert data.get("number_of_flagged_trades") == expected_data["number_of_flagged_trades"], "Incorrect number_of_flagged_trades"


def _script_command(path):
    suffix = path.suffix.lower()
    if suffix == ".py":
        return ["python3", str(path)]
    if suffix == ".sh":
        return ["bash", str(path)]
    if suffix == ".js" and shutil.which("node"):
        return ["node", str(path)]
    if suffix == ".rb" and shutil.which("ruby"):
        return ["ruby", str(path)]
    if suffix == ".pl" and shutil.which("perl"):
        return ["perl", str(path)]
    try:
        first_line = path.open("r", errors="ignore").readline().strip()
    except OSError:
        first_line = ""
    if first_line.startswith("#!"):
        interpreter = shlex.split(first_line[2:].strip())
        if interpreter:
            return interpreter + [str(path)]
    if os.access(path, os.X_OK):
        return [str(path)]
    return None


def test_report_is_generated_by_aggregation_script():
    db_path = Path("/app/trading/users.db")
    logs_path = Path("/app/trading/executions.jsonl")
    report_path = Path("/home/user/audit_report.json")

    candidates = []
    for path in Path("/home/user").rglob("*"):
        if not path.is_file() or path == report_path:
            continue
        command = _script_command(path)
        if command is not None:
            candidates.append((path, command))
    assert candidates, "No aggregation script was found under /home/user"

    token = secrets.token_hex(6)
    expected_name = f"Audit Employee {token}"
    expected_department = f"Dynamic Desk {token}"
    expected_risk = secrets.randbelow(8) + 1
    amounts = [
        float(secrets.randbelow(90000) + 1000) + 0.25,
        float(secrets.randbelow(90000) + 1000) + 0.50,
        float(secrets.randbelow(90000) + 1000) + 0.75,
        float(secrets.randbelow(90000) + 1000),
    ]
    flags = [True, False, True, bool(secrets.randbelow(2))]
    expected_total = float(sum(amounts))
    expected_flagged = sum(1 for value in flags if value)

    with tempfile.TemporaryDirectory() as backup_dir:
        original_db = Path(backup_dir) / "users.db.original"
        original_logs = Path(backup_dir) / "executions.jsonl.original"
        dynamic_db = Path(backup_dir) / "users.db.dynamic"
        dynamic_logs = Path(backup_dir) / "executions.jsonl.dynamic"
        shutil.copy2(db_path, original_db)
        shutil.copy2(logs_path, original_logs)
        original_report = report_path.read_bytes() if report_path.exists() else None

        try:
            conn = sqlite3.connect(db_path)
            try:
                row = conn.execute(
                    "SELECT department_id FROM employees WHERE employee_id = ?",
                    ("E-7734",),
                ).fetchone()
                assert row is not None
                department_id = row[0]
                conn.execute(
                    "UPDATE employees SET name = ? WHERE employee_id = ?",
                    (expected_name, "E-7734"),
                )
                conn.execute(
                    "UPDATE departments SET department_name = ?, risk_level = ? WHERE department_id = ?",
                    (expected_department, expected_risk, department_id),
                )
                conn.commit()
            finally:
                conn.close()

            records = [
                {"employee_id": "E-7734", "amount": amount, "is_flagged": flag}
                for amount, flag in zip(amounts, flags)
            ]
            records.extend([
                {"employee_id": "E-1234", "amount": 9876543.25, "is_flagged": True},
                {"employee_id": "E-DECOY", "amount": 1234567.50, "is_flagged": True},
            ])
            with logs_path.open("w") as handle:
                for record in records:
                    handle.write(json.dumps(record) + "\n")

            shutil.copy2(db_path, dynamic_db)
            shutil.copy2(logs_path, dynamic_logs)

            expected = {
                "employee_id": "E-7734",
                "name": expected_name,
                "department_name": expected_department,
                "risk_level": expected_risk,
                "total_trade_volume": expected_total,
                "number_of_flagged_trades": expected_flagged,
            }

            successes = []
            diagnostics = []
            for path, command in candidates:
                shutil.copy2(dynamic_db, db_path)
                shutil.copy2(dynamic_logs, logs_path)
                if report_path.exists():
                    report_path.unlink()
                try:
                    result = subprocess.run(
                        command,
                        cwd="/home/user",
                        capture_output=True,
                        text=True,
                        timeout=15,
                    )
                except (OSError, subprocess.TimeoutExpired) as exc:
                    diagnostics.append(f"{path.name}: {exc}")
                    continue

                if not report_path.is_file():
                    diagnostics.append(f"{path.name}: did not create audit_report.json")
                    continue
                try:
                    generated = json.loads(report_path.read_text())
                except (OSError, json.JSONDecodeError) as exc:
                    diagnostics.append(f"{path.name}: invalid report: {exc}")
                    continue

                correct_types = (
                    type(generated.get("employee_id")) is str
                    and type(generated.get("name")) is str
                    and type(generated.get("department_name")) is str
                    and type(generated.get("risk_level")) is int
                    and type(generated.get("total_trade_volume")) is float
                    and type(generated.get("number_of_flagged_trades")) is int
                )
                if result.returncode == 0 and correct_types and all(
                    generated.get(key) == value for key, value in expected.items()
                ):
                    successes.append(path)
                    break
                diagnostics.append(f"{path.name}: generated incorrect dynamic report")

            assert successes, (
                "No submitted script regenerated the audit report from changed database and JSONL inputs. "
                + " | ".join(diagnostics[-6:])
            )
        finally:
            shutil.copy2(original_db, db_path)
            shutil.copy2(original_logs, logs_path)
            if original_report is None:
                if report_path.exists():
                    report_path.unlink()
            else:
                report_path.write_bytes(original_report)


def _check_validator_case(validator_script, payload, expected_stdout, expected_code, directory):
    filename = f"case_{secrets.token_hex(8)}.json"
    path = Path(directory) / filename
    path.write_text(json.dumps(payload))
    result = subprocess.run(
        ["python3", validator_script, str(path)],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == expected_code, (
        f"Validator returned {result.returncode} for {payload!r}; output={result.stdout!r}"
    )
    assert expected_stdout in result.stdout, (
        f"Validator did not print {expected_stdout} for {payload!r}"
    )


def test_adversarial_validator():
    validator_script = "/home/user/query_validator.py"
    assert os.path.isfile(validator_script), f"Validator script not found at {validator_script}"
    assert os.access(validator_script, os.X_OK), f"Validator script is not executable: {validator_script}"

    evil_dir = "/app/corpora/evil/"
    clean_dir = "/app/corpora/clean/"

    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]

    evil_bypassed = []
    clean_rejected = []

    for filepath in evil_files:
        result = subprocess.run(["python3", validator_script, filepath], capture_output=True, text=True)
        if result.returncode != 1 or "REJECT" not in result.stdout:
            evil_bypassed.append(os.path.basename(filepath))

    for filepath in clean_files:
        result = subprocess.run(["python3", validator_script, filepath], capture_output=True, text=True)
        if result.returncode != 0 or "ACCEPT" not in result.stdout:
            clean_rejected.append(os.path.basename(filepath))

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_rejected:
        error_msgs.append(f"{len(clean_rejected)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_rejected)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))

    malicious = [
        {"filters": {"account": "guest' OR '1'='1"}},
        {"filters": {"symbol": "x UNION SELECT password FROM users"}},
        {"filters": {"comment": "valid-prefix-- discard predicate"}},
        {"filters": {"trade_id": "42; dRoP TABLE executions"}},
    ]
    clean = [
        {"filters": {"owner": "O'Reilly", "status": "active", "desk": "fixed income"}},
        {"filters": {"description": "union membership selected", "trade_id": "A-12345"}},
        {"filters": {"region": "north-west", "limit": "1000", "date": "2026-09-11"}},
    ]

    with tempfile.TemporaryDirectory(prefix="validator_cases_") as directory:
        for payload in malicious:
            _check_validator_case(validator_script, payload, "REJECT", 1, directory)
        for payload in clean:
            _check_validator_case(validator_script, payload, "ACCEPT", 0, directory)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
