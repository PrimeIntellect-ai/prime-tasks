#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import json
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile

SCRIPT = "/home/user/process_configs.sh"
DB = "/home/user/config_inventory.db"
STATS = "/home/user/stats.csv"
DUMPS = "/home/user/config_dumps"


def sha(data):
    return hashlib.sha256(data.encode("utf-8")).hexdigest()


def schema(conn):
    return conn.execute("PRAGMA table_info(configs)").fetchall()


def assert_exact_schema(conn):
    assert schema(conn) == [
        (0, "hash", "TEXT", 0, None, 1),
        (1, "server_id", "TEXT", 0, None, 0),
        (2, "timestamp", "TEXT", 0, None, 0),
        (3, "data", "TEXT", 0, None, 0),
    ], f"Unexpected configs schema: {schema(conn)!r}"


def cron_output():
    try:
        return subprocess.check_output(
            ["crontab", "-l", "-u", "user"], text=True,
            stderr=subprocess.STDOUT
        )
    except subprocess.CalledProcessError as exc:
        return exc.output


def test_script_exists_and_executable():
    script_path = "/home/user/process_configs.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."
    with open(script_path, encoding="utf-8", errors="replace") as f:
        first_line = f.readline()
    assert first_line.startswith("#!") and "bash" in first_line, "The required artifact must be a Bash script."


def test_parallel_processing_is_implemented():
    with open(SCRIPT, encoding="utf-8", errors="replace") as f:
        code = f.read()
    active = "\n".join(
        line for line in code.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    )
    uses_parallel = re.search(r"(?m)(?:^|[|;&]\s*)parallel(?:\s|$)", active)
    uses_xargs = re.search(
        r"\bxargs\b[^\n]*(?:-P\s*[2-9][0-9]*|--max-procs(?:=|\s+)[2-9][0-9]*)",
        active,
    )
    background_ops = re.findall(r"(?<![>&])&(?![>&])", active)
    uses_background_workers = background_ops and re.search(r"\bwait\b", active)
    uses_python_processes = re.search(r"\b(?:multiprocessing|ProcessPoolExecutor)\b", active)
    assert uses_parallel or uses_xargs or uses_background_workers or uses_python_processes, \
        "No implementation of processing with at least two concurrent processes was found."


def test_cron_job_configured():
    output = cron_output()
    assert "0 * * * * /home/user/process_configs.sh" in output, "Cron job is not configured correctly for 'user'."
    active = [line.strip() for line in output.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    invoking_script = [line for line in active if "/home/user/process_configs.sh" in line]
    assert invoking_script == ["0 * * * * /home/user/process_configs.sh"], \
        f"Expected exactly one top-of-hour cron entry, got: {invoking_script!r}"


def test_database_records():
    db_path = "/home/user/config_inventory.db"
    assert os.path.isfile(db_path), f"Database {db_path} does not exist."
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='configs';")
    assert cursor.fetchone() is not None, "Table 'configs' does not exist in the database."
    assert_exact_schema(conn)

    cursor.execute("SELECT COUNT(*) FROM configs;")
    count = cursor.fetchone()[0]
    assert count == 3, f"Expected 3 records in the database, found {count}."

    cursor.execute("SELECT server_id FROM configs WHERE data=?;", ("port=80\nmode=active",))
    row = cursor.fetchone()
    assert row is not None, "Record for 'port=80\\nmode=active' is missing."
    assert row[0] == "srv2", f"Expected server_id 'srv2' for 'port=80\\nmode=active', got {row[0]}."

    cursor.execute("SELECT server_id FROM configs WHERE data=?;", ("port=8080\nmode=passive",))
    row = cursor.fetchone()
    assert row is not None, "Record for 'port=8080\\nmode=passive' is missing."
    assert row[0] == "srv1", f"Expected server_id 'srv1' for 'port=8080\\nmode=passive', got {row[0]}."

    cursor.execute("SELECT server_id FROM configs WHERE data=?;", ("port=443\nmode=active",))
    row = cursor.fetchone()
    assert row is not None, "Record for 'port=443\\nmode=active' is missing."
    assert row[0] == "srv3", f"Expected server_id 'srv3' for 'port=443\\nmode=active', got {row[0]}."

    expected = {
        (sha("port=80\nmode=active"), "srv2", "2023-10-01T09:30:00Z", "port=80\nmode=active"),
        (sha("port=8080\nmode=passive"), "srv1", "2023-10-01T11:00:00Z", "port=8080\nmode=passive"),
        (sha("port=443\nmode=active"), "srv3", "2023-10-01T08:00:00Z", "port=443\nmode=active"),
    }
    actual = set(cursor.execute("SELECT hash, server_id, timestamp, data FROM configs"))
    assert actual == expected, f"Database rows, hashes, or timestamps are incorrect: {actual!r}"
    conn.close()


def test_stats_csv():
    csv_path = "/home/user/stats.csv"
    assert os.path.isfile(csv_path), f"Stats file {csv_path} does not exist."
    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    assert len(lines) == 4, f"Expected 4 lines in stats.csv (1 header + 3 data), found {len(lines)}."
    assert lines[0] == "hash,server_count", f"Expected header 'hash,server_count', got '{lines[0]}'."

    hash_passive = hashlib.sha256(b"port=8080\nmode=passive").hexdigest()
    hash_active_80 = hashlib.sha256(b"port=80\nmode=active").hexdigest()
    hash_active_443 = hashlib.sha256(b"port=443\nmode=active").hexdigest()
    expected_lines = [f"{hash_passive},2", f"{hash_active_80},2", f"{hash_active_443},1"]
    expected_lines.sort(key=lambda x: (-int(x.split(',')[1]), x.split(',')[0]))
    for i, expected in enumerate(expected_lines):
        assert lines[i + 1] == expected, \
            f"Line {i+2} in stats.csv is incorrect. Expected '{expected}', got '{lines[i+1]}'."


def test_z_script_executes_correctly_on_changed_inputs():
    data_a = "greeting=Hello\nsnowman=☃"
    data_b = "quoted=\"yes\", path=/tmp\nemoji=😀"
    data_c = ""
    records_by_file = {
        "new1.jsonl": [
            {"server_id": "new-a", "timestamp": "2025-02-01T12:00:00Z", "config_data": data_a},
            {"server_id": "new-b", "timestamp": "2025-02-01T08:00:00Z", "config_data": data_b},
        ],
        "new2.jsonl": [
            {"server_id": "new-c", "timestamp": "2025-02-01T09:00:00Z", "config_data": data_a},
            {"server_id": "new-d", "timestamp": "2025-02-01T13:00:00Z", "config_data": data_b},
        ],
        "new3.jsonl": [
            {"server_id": "new-earliest", "timestamp": "2025-02-01T07:30:00Z", "config_data": data_a},
            {"server_id": "new-empty", "timestamp": "2025-02-01T06:00:00Z", "config_data": data_c},
        ],
    }

    parent = tempfile.mkdtemp(prefix="config-verifier-", dir="/home/user")
    backup = os.path.join(parent, "original_dumps")
    os.rename(DUMPS, backup)
    os.mkdir(DUMPS, 0o755)
    try:
        for filename, records in records_by_file.items():
            path = os.path.join(DUMPS, filename)
            with open(path, "w", encoding="utf-8") as f:
                for record in records:
                    # ensure_ascii forces non-ASCII content to be represented by JSON Unicode escapes.
                    f.write(json.dumps(record, ensure_ascii=True) + "\n")
            os.chmod(path, 0o644)
        os.chown(DUMPS, 1000, 1000)
        for filename in records_by_file:
            os.chown(os.path.join(DUMPS, filename), 1000, 1000)

        for output in (DB, STATS):
            if os.path.lexists(output):
                if os.path.isdir(output):
                    shutil.rmtree(output)
                else:
                    os.remove(output)

        result = subprocess.run(
            ["runuser", "-u", "user", "--", SCRIPT],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60
        )
        assert result.returncode == 0, f"Script failed on changed inputs:\n{result.stdout}"
        assert os.path.isfile(DB), "Executing the script did not create the database."
        assert os.path.isfile(STATS), "Executing the script did not create stats.csv."

        expected_rows = {
            (sha(data_a), "new-earliest", "2025-02-01T07:30:00Z", data_a),
            (sha(data_b), "new-b", "2025-02-01T08:00:00Z", data_b),
            (sha(data_c), "new-empty", "2025-02-01T06:00:00Z", data_c),
        }
        conn = sqlite3.connect(DB)
        assert_exact_schema(conn)
        actual_rows = set(conn.execute("SELECT hash, server_id, timestamp, data FROM configs"))
        conn.close()
        assert actual_rows == expected_rows, f"Changed-input database is incorrect: {actual_rows!r}"

        expected_stats = sorted(
            [(sha(data_a), "3"), (sha(data_b), "2"), (sha(data_c), "1")],
            key=lambda row: (-int(row[1]), row[0]),
        )
        with open(STATS, newline="", encoding="utf-8") as f:
            actual_stats = list(csv.reader(f))
        assert actual_stats == [["hash", "server_count"], *[list(row) for row in expected_stats]], \
            f"Changed-input stats.csv is incorrect: {actual_stats!r}"
    finally:
        if os.path.exists(DUMPS):
            shutil.rmtree(DUMPS)
        os.rename(backup, DUMPS)
        shutil.rmtree(parent, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
