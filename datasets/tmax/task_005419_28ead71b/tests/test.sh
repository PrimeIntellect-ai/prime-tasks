#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import sqlite3
import string
import subprocess

SCRIPT_PATH = '/home/user/etl.sh'
DB_PATH = '/home/user/metrics.db'
EXPECTED_SCHEMA = [
    ('timestamp', 'TEXT'),
    ('level', 'TEXT'),
    ('code', 'INTEGER'),
    ('user', 'TEXT'),
    ('ip', 'TEXT'),
]


def assert_incidents_schema(conn):
    info = conn.execute("PRAGMA table_info(incidents)").fetchall()
    actual = [(row[1], row[2].upper()) for row in info]
    assert actual == EXPECTED_SCHEMA, (
        "Table 'incidents' does not have the required schema. "
        f"Expected {EXPECTED_SCHEMA}, got {actual}."
    )


def test_etl_script_executable():
    assert os.path.isfile(SCRIPT_PATH), f"ETL script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"ETL script {SCRIPT_PATH} is not executable."


def test_parsed_csv_contents():
    csv_path = '/home/user/parsed.csv'
    assert os.path.isfile(csv_path), f"Parsed CSV {csv_path} does not exist."

    with open(csv_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "2024-05-12T08:15:30,WARN,404,admincode,192.168.1.5",
        "2024-05-12T08:16:05,ERROR,500,sysadmin,10.0.0.9",
        "2024-05-12T08:17:22,INFO,NULL,bob,NULL",
        "2024-05-12T08:18:00,CRITICAL,503,NULL,172.16.0.4"
    ]

    assert lines == expected_lines, f"Contents of {csv_path} do not match the expected normalized output."


def test_sqlite_database_contents_and_schema():
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='incidents';")
    assert cursor.fetchone() is not None, "Table 'incidents' does not exist in the database."
    assert_incidents_schema(conn)

    cursor.execute("SELECT timestamp, level, code, user, ip FROM incidents ORDER BY timestamp ASC;")
    rows = cursor.fetchall()
    conn.close()

    expected_rows = [
        ("2024-05-12T08:15:30", "WARN", 404, "admincode", "192.168.1.5"),
        ("2024-05-12T08:16:05", "ERROR", 500, "sysadmin", "10.0.0.9"),
        ("2024-05-12T08:17:22", "INFO", "NULL", "bob", "NULL"),
        ("2024-05-12T08:18:00", "CRITICAL", 503, "NULL", "172.16.0.4")
    ]

    normalized_rows = [tuple(str(item) for item in row) for row in rows]
    expected_normalized = [tuple(str(item) for item in row) for row in expected_rows]
    assert normalized_rows == expected_normalized, "Database contents do not match the expected data."


def test_cron_schedule_file():
    txt_path = '/home/user/cron_schedule.txt'
    assert os.path.isfile(txt_path), f"Cron schedule file {txt_path} does not exist."

    with open(txt_path, 'r') as f:
        content = f.read().strip()

    content_normalized = re.sub(r'\s+', ' ', content)
    expected_normalized = "15 * * * * /home/user/etl.sh /home/user/incoming.log /home/user/parsed.csv"
    assert expected_normalized in content_normalized, f"File {txt_path} does not contain the correct cron expression."


def test_cron_job_installed():
    try:
        result = subprocess.run(
            ['crontab', '-u', 'user', '-l'], capture_output=True, text=True, check=True
        )
        crontab_content = result.stdout
    except subprocess.CalledProcessError:
        crontab_content = ""

    crontab_normalized = re.sub(r'\s+', ' ', crontab_content)
    expected_cmd = "15 * * * * /home/user/etl.sh /home/user/incoming.log /home/user/parsed.csv"
    assert expected_cmd in crontab_normalized, "The cron job was not correctly installed for the 'user' account."


def _mixed_case(value):
    return ''.join(ch.upper() if i % 2 == 0 else ch.lower() for i, ch in enumerate(value))


def _random_word(length=10):
    return ''.join(secrets.choice(string.ascii_lowercase) for _ in range(length))


def _write_user_input(path, lines):
    with open(path, 'w') as f:
        f.write('\n'.join(lines) + '\n')
    user_stat = os.stat('/home/user')
    os.chown(path, user_stat.st_uid, user_stat.st_gid)
    os.chmod(path, 0o644)


def _run_and_check(input_path, output_path, expected):
    result = subprocess.run(
        ['runuser', '-u', 'user', '--', SCRIPT_PATH, input_path, output_path],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"ETL script failed on a new input (exit {result.returncode}).\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.isfile(output_path), "ETL script did not create the requested output CSV."

    with open(output_path, 'r') as f:
        actual_csv = [line.rstrip('\r\n') for line in f if line.strip()]
    expected_csv = [','.join(str(value) for value in row) for row in expected]
    assert actual_csv == expected_csv, "ETL script produced incorrect CSV output for a new input."

    assert os.path.isfile(DB_PATH), "ETL script did not create /home/user/metrics.db."
    conn = sqlite3.connect(DB_PATH)
    try:
        exists = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='incidents'"
        ).fetchone()
        assert exists is not None, "ETL script did not create the incidents table."
        assert_incidents_schema(conn)
        rows = conn.execute(
            "SELECT timestamp, level, code, user, ip FROM incidents ORDER BY timestamp"
        ).fetchall()
    finally:
        conn.close()

    actual_rows = [tuple(str(value) for value in row) for row in rows]
    expected_rows = [tuple(str(value) for value in row) for row in expected]
    assert actual_rows == expected_rows, (
        "Database does not contain exactly the rows from the latest ETL run."
    )


def test_z_etl_executes_on_new_inputs_and_replaces_database_contents():
    token = secrets.token_hex(6)
    input_one = f'/home/user/.verifier_input_{token}_1.log'
    input_two = f'/home/user/.verifier_input_{token}_2.log'
    output_one = f'/home/user/.verifier_output_{token}_1.csv'
    output_two = f'/home/user/.verifier_output_{token}_2.csv'

    user_one = _mixed_case(_random_word())
    user_two = _mixed_case(_random_word())
    user_three = _mixed_case(_random_word())
    code_one = secrets.randbelow(700) + 100
    code_two = secrets.randbelow(700) + 100
    code_three = secrets.randbelow(700) + 100
    ip_one = f"10.{secrets.randbelow(200)+1}.{secrets.randbelow(200)+1}.{secrets.randbelow(200)+1}"
    ip_two = f"172.20.{secrets.randbelow(200)+1}.{secrets.randbelow(200)+1}"
    ip_three = f"192.0.2.{secrets.randbelow(200)+1}"

    lines_one = [
        f'[2031-07-08T01:02:03] CoDe={code_one} USER={user_one} msg="alpha event" iP={ip_one} LeVeL=wArN',
        '[2031-07-08T01:02:04] msg="missing fields" LEVEL=info',
        f'[2031-07-08T01:02:05] IP={ip_two} level=Error user={user_two} code={code_two} msg="omega"',
    ]
    expected_one = [
        ('2031-07-08T01:02:03', 'WARN', code_one, user_one.lower(), ip_one),
        ('2031-07-08T01:02:04', 'INFO', 'NULL', 'NULL', 'NULL'),
        ('2031-07-08T01:02:05', 'ERROR', code_two, user_two.lower(), ip_two),
    ]

    lines_two = [
        f'[2032-09-10T11:12:13] user={user_three} LEVEL=critical IP={ip_three} CODE={code_three} msg="second run"',
        '[2032-09-10T11:12:14] level=debug msg="no identity"',
    ]
    expected_two = [
        ('2032-09-10T11:12:13', 'CRITICAL', code_three, user_three.lower(), ip_three),
        ('2032-09-10T11:12:14', 'DEBUG', 'NULL', 'NULL', 'NULL'),
    ]

    _write_user_input(input_one, lines_one)
    _write_user_input(input_two, lines_two)

    if os.path.lexists(DB_PATH):
        os.remove(DB_PATH)

    _run_and_check(input_one, output_one, expected_one)
    _run_and_check(input_two, output_two, expected_two)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
