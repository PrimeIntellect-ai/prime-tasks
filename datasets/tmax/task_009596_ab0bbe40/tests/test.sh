#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3

DB_PATH = '/home/user/metrics.db'
ETL_PATH = '/home/user/etl.py'

def test_etl_exists():
    assert os.path.isfile(ETL_PATH), f"The ETL script {ETL_PATH} was not created."

def test_db_exists():
    assert os.path.isfile(DB_PATH), f"The database file {DB_PATH} was not created."

def test_table_exists():
    assert os.path.isfile(DB_PATH), "Database missing, cannot check for table."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='hourly_metrics';")
    table = cursor.fetchone()
    conn.close()
    assert table is not None, "The table 'hourly_metrics' does not exist in the database."

def test_table_schema():
    assert os.path.isfile(DB_PATH), "Database missing, cannot check schema."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(hourly_metrics);")
    columns = {row[1]: row[2].upper() for row in cursor.fetchall()}
    conn.close()

    expected_columns = {
        'bucket_hour': 'TEXT',
        'ip_address': 'TEXT',
        'avg_cpu': 'REAL',
        'max_mem': 'INTEGER'
    }

    for col_name, col_type in expected_columns.items():
        assert col_name in columns, f"Column '{col_name}' is missing from 'hourly_metrics'."
        assert columns[col_name].startswith(col_type), f"Column '{col_name}' has incorrect type. Expected {col_type}, got {columns[col_name]}."

def test_table_contents():
    assert os.path.isfile(DB_PATH), "Database missing, cannot check contents."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT bucket_hour, ip_address, avg_cpu, max_mem FROM hourly_metrics ORDER BY bucket_hour ASC, ip_address ASC;")
    rows = cursor.fetchall()
    conn.close()

    expected_rows = [
        ('2023-10-01 14:00:00', '192.168.1.10', 50.0, 2048),
        ('2023-10-01 15:00:00', '10.0.0.5', 85.0, 8192),
        ('2023-10-01 16:00:00', '192.168.1.10', 30.0, 512)
    ]

    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in 'hourly_metrics', but found {len(rows)}."

    for i, (actual, expected) in enumerate(zip(rows, expected_rows)):
        assert actual[0] == expected[0], f"Row {i+1}: Expected bucket_hour {expected[0]}, got {actual[0]}."
        assert actual[1] == expected[1], f"Row {i+1}: Expected ip_address {expected[1]}, got {actual[1]}."
        assert abs(actual[2] - expected[2]) < 1e-5, f"Row {i+1}: Expected avg_cpu {expected[2]}, got {actual[2]}."
        assert actual[3] == expected[3], f"Row {i+1}: Expected max_mem {expected[3]}, got {actual[3]}."
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_etl.py
import os
import secrets
import shutil
import sqlite3
import stat
import subprocess
import sys

ETL_PATH = '/home/user/etl.py'
RAW_DIR = '/home/user/raw_logs'
DB_PATH = '/home/user/metrics.db'

assert os.path.isfile(ETL_PATH), f"The ETL script {ETL_PATH} was not created."
assert stat.S_ISREG(os.stat(ETL_PATH).st_mode), f"{ETL_PATH} is not a regular file."

rng = secrets.SystemRandom()
year = rng.randint(2024, 2032)
month = rng.randint(1, 9)
day = rng.randint(1, 20)
hour = rng.randint(2, 20)
date = f"{year:04d}-{month:02d}-{day:02d}"

ip_a = f"172.20.{rng.randint(1, 240)}.{rng.randint(1, 240)}"
ip_b = f"10.{rng.randint(1, 240)}.{rng.randint(1, 240)}.{rng.randint(1, 240)}"
ip_c = f"192.168.{rng.randint(2, 240)}.{rng.randint(1, 240)}"

cpu_a1 = rng.randint(10, 35)
cpu_a2 = rng.randint(60, 90)
cpu_a3 = rng.randint(20, 75)
cpu_b1 = rng.randint(5, 40)
cpu_b2 = rng.randint(55, 95)
cpu_c = rng.randint(15, 85)
mem_a1 = rng.randint(500, 1500)
mem_a2 = rng.randint(2000, 4000)
mem_a3 = rng.randint(600, 1800)
mem_b1 = rng.randint(1000, 3000)
mem_b2 = rng.randint(4000, 8000)
mem_c = rng.randint(700, 5000)

def line(h, minute, second, ip, cpu, mem, status='OK'):
    return f"[{date} {h:02d}:{minute:02d}:{second:02d}] IP:{ip} CPU:{cpu}% MEM:{mem}MB STATUS:{status}\n"

utf16_data = ''.join([
    line(hour, 3, 11, ip_a, cpu_a1, mem_a1),
    line(hour, 49, 57, ip_a, cpu_a2, mem_a2, 'WARNING'),
    line(hour + 1, 10, 0, ip_a, cpu_a3, mem_a3),
    line(hour, 30, 0, ip_a, 101, 9999),
    line(hour, 31, 0, ip_a, -1, 9999),
    line(hour, 32, 0, '300.1.2.3', 50, 9999),
    line(hour, 33, 0, ip_a, 99, 9999).rstrip('\n') + ' trailing-junk\n',
])

iso_data = ''.join([
    line(hour + 1, 5, 0, ip_b, cpu_b1, mem_b1),
    line(hour + 1, 55, 0, ip_b, cpu_b2, mem_b2, 'DEGRADED'),
    line(hour + 2, 25, 0, ip_c, cpu_c, mem_c),
    'Corrupted café log line without proper formatting...\n',
    line(hour + 2, 30, 0, '999.999.1.1', 40, 9999),
])

shutil.rmtree(RAW_DIR, ignore_errors=True)
os.makedirs(RAW_DIR)
token = secrets.token_hex(8)
with open(os.path.join(RAW_DIR, f"legacy-{token}.log"), 'w', encoding='utf-16le') as f:
    f.write(utf16_data)
with open(os.path.join(RAW_DIR, f"archive-{token}.log"), 'w', encoding='iso-8859-1') as f:
    f.write(iso_data)
with open(os.path.join(RAW_DIR, f"ignore-{token}.txt"), 'w', encoding='utf-8') as f:
    f.write(line(hour, 0, 0, '8.8.8.8', 100, 99999))

if os.path.exists(DB_PATH):
    os.remove(DB_PATH)

result = subprocess.run(
    [sys.executable, ETL_PATH],
    cwd='/home/user',
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    timeout=30,
)
assert result.returncode == 0, f"ETL script failed when executed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
assert os.path.isfile(DB_PATH), "Executing etl.py did not create metrics.db."

conn = sqlite3.connect(DB_PATH)
try:
    table = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='hourly_metrics';").fetchone()
    assert table is not None, "Executing etl.py did not create hourly_metrics."

    columns = {row[1]: row[2].upper() for row in conn.execute("PRAGMA table_info(hourly_metrics);").fetchall()}
    expected_columns = {
        'bucket_hour': 'TEXT',
        'ip_address': 'TEXT',
        'avg_cpu': 'REAL',
        'max_mem': 'INTEGER',
    }
    for name, declared_type in expected_columns.items():
        assert name in columns, f"Column '{name}' is missing from dynamically generated output."
        assert columns[name].startswith(declared_type), f"Column '{name}' has incorrect type. Expected {declared_type}, got {columns[name]}."

    rows = conn.execute(
        "SELECT bucket_hour, ip_address, avg_cpu, max_mem "
        "FROM hourly_metrics ORDER BY bucket_hour, ip_address"
    ).fetchall()
finally:
    conn.close()

expected = sorted([
    (f"{date} {hour:02d}:00:00", ip_a, (cpu_a1 + cpu_a2) / 2.0, max(mem_a1, mem_a2)),
    (f"{date} {hour + 1:02d}:00:00", ip_a, float(cpu_a3), mem_a3),
    (f"{date} {hour + 1:02d}:00:00", ip_b, (cpu_b1 + cpu_b2) / 2.0, max(mem_b1, mem_b2)),
    (f"{date} {hour + 2:02d}:00:00", ip_c, float(cpu_c), mem_c),
], key=lambda row: (row[0], row[1]))

assert len(rows) == len(expected), f"Expected {len(expected)} dynamic rows, found {len(rows)}: {rows!r}"
for index, (actual, wanted) in enumerate(zip(rows, expected), 1):
    assert actual[0] == wanted[0], f"Dynamic row {index}: wrong bucket: {actual!r}"
    assert actual[1] == wanted[1], f"Dynamic row {index}: wrong IP: {actual!r}"
    assert isinstance(actual[2], (int, float)), f"Dynamic row {index}: avg_cpu is not numeric."
    assert abs(float(actual[2]) - wanted[2]) < 1e-5, f"Dynamic row {index}: wrong average CPU: {actual!r}"
    assert actual[3] == wanted[3], f"Dynamic row {index}: wrong maximum memory: {actual!r}"
DYNAMIC_EOF

passed=1
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1 || passed=0
if [ "$passed" -eq 1 ]; then
    python3 /tmp/test_dynamic_etl.py 2>&1 || passed=0
fi

if [ "$passed" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
