#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import re
import subprocess
from collections import Counter

import pytest

SCRIPT_PATH = "/home/user/etl.sh"
RAW_PATH = "/home/user/raw_data.log"
ALERTS_PATH = "/home/user/alerts.csv"


def test_etl_script_exists_and_executable():
    """Check if the ETL script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"ETL script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"ETL script {SCRIPT_PATH} is not executable."

    # The requested ISO-8859-1 to UTF-8 conversion must be represented in the
    # implementation. Normalize spelling so common iconv/Python aliases work.
    with open(SCRIPT_PATH, "r", encoding="utf-8", errors="replace") as f:
        normalized = re.sub(r"[^a-z0-9]", "", f.read().lower())
    assert ("iso88591" in normalized or "latin1" in normalized), \
        "ETL script does not specify ISO-8859-1/Latin-1 input decoding."
    assert "utf8" in normalized, "ETL script does not specify UTF-8 conversion."


def test_alerts_csv_content():
    """Preserve the original check that the required manual run was performed."""
    assert os.path.isfile(ALERTS_PATH), f"Alerts file {ALERTS_PATH} does not exist."

    with open(ALERTS_PATH, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "2023-10-24T14,3",
        "2023-10-24T16,4"
    ]

    assert lines == expected_lines, \
        f"Alerts file content is incorrect. Expected {expected_lines}, got {lines}."


def expected_alerts_from_iso8859_1(raw_bytes):
    counts = Counter()
    for line in raw_bytes.decode("iso-8859-1").splitlines():
        fields = line.split("|")
        assert len(fields) == 4
        timestamp = fields[0].strip()
        status = fields[2].strip()
        if status == "500":
            counts[timestamp[:13]] += 1
    return [f"{hour},{counts[hour]}" for hour in sorted(counts) if counts[hour] > 2]


def run_fixture(records):
    random.SystemRandom().shuffle(records)
    text = "\n".join(
        f"{timestamp} | {server} | {status} | {message}"
        for timestamp, server, status, message in records
    ) + "\n"
    raw_bytes = text.encode("iso-8859-1")
    expected = expected_alerts_from_iso8859_1(raw_bytes)

    with open(RAW_PATH, "wb") as f:
        f.write(raw_bytes)
    user = pwd.getpwnam("user")
    os.chown(RAW_PATH, user.pw_uid, user.pw_gid)
    if os.path.lexists(ALERTS_PATH):
        os.unlink(ALERTS_PATH)

    result = subprocess.run(
        ["runuser", "-u", "user", "--", "/bin/bash", SCRIPT_PATH],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, \
        f"ETL script failed on a verification fixture: {result.stderr}"
    assert os.path.isfile(ALERTS_PATH), "ETL script did not create alerts.csv."

    with open(ALERTS_PATH, "r", encoding="utf-8") as f:
        actual = f.read().splitlines()
    assert all(re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2},\d+", line) for line in actual), \
        f"alerts.csv contains incorrectly formatted rows: {actual}"
    assert actual == expected, f"Expected derived alerts {expected}, got {actual}."


def test_etl_executes_and_handles_changed_iso8859_1_input():
    """Execute the submitted artifact on non-original inputs with derived answers."""
    rng = random.SystemRandom()
    day = rng.randint(10, 25)
    base = f"203{rng.randint(1, 7)}-07-{day:02d}"
    records = []

    # Exactly two 500s: threshold is strict, so this hour must be omitted.
    for minute in (3, 41):
        records.append((f"{base}T04:{minute:02d}:00Z", "srv-a", "500", "Échec réseau"))
    records.append((f"{base}T04:55:00Z", "srv-b", "200", "Succès"))

    # Three and four failures in two different hours must be emitted and sorted.
    for minute in (2, 17, 53):
        records.append((f"{base}T19:{minute:02d}:00Z", "srv-c", "500", "Système défaillant"))
    for minute in (1, 11, 31, 59):
        records.append((f"{base}T08:{minute:02d}:00Z", "srv-d", "500", "Connexion échouée"))
    records.extend([
        (f"{base}T08:22:00Z", "srv-z", "404", "Non trouvé"),
        (f"{base}T22:12:00Z", "srv-z", "500", "Délai dépassé"),
    ])
    run_fixture(records)

    # A second execution verifies that output is regenerated rather than appended
    # or retained from a previous input.
    base2 = f"204{rng.randint(1, 7)}-11-{rng.randint(10, 25):02d}"
    records2 = [
        (f"{base2}T13:{minute:02d}:00Z", "srv-x", "500", "Erreur interne")
        for minute in (5, 15, 25)
    ]
    records2.extend([
        (f"{base2}T12:01:00Z", "srv-y", "500", "Panne"),
        (f"{base2}T12:02:00Z", "srv-y", "500", "Panne"),
        (f"{base2}T14:03:00Z", "srv-y", "200", "Très bien"),
    ])
    run_fixture(records2)


def test_crontab_scheduled():
    """Check if the ETL script is scheduled in the crontab."""
    try:
        result = subprocess.run(
            ["crontab", "-l", "-u", "user"],
            capture_output=True,
            text=True,
            check=True
        )
        crontab_output = result.stdout
    except subprocess.CalledProcessError:
        try:
            result = subprocess.run(
                ["crontab", "-l"],
                capture_output=True,
                text=True,
                check=True
            )
            crontab_output = result.stdout
        except subprocess.CalledProcessError:
            pytest.fail("Failed to retrieve crontab. Is it set?")

    expected_cron_job = "15 * * * * /bin/bash /home/user/etl.sh"

    # Preserve the original assertion.
    matching_lines = [
        line for line in crontab_output.splitlines()
        if "15" in line and "*" in line and "/bin/bash /home/user/etl.sh" in line
    ]
    assert matching_lines, \
        f"Crontab does not contain the expected scheduled job: {expected_cron_job}"

    # Also require the actual five schedule fields and command to be exact.
    exact_lines = [
        line for line in crontab_output.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
        and line.split() == ["15", "*", "*", "*", "*", "/bin/bash", "/home/user/etl.sh"]
    ]
    assert exact_lines, \
        f"Crontab does not contain the exact scheduled job: {expected_cron_job}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
