#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import sqlite3
import subprocess
from collections import Counter

import pytest

EXPECTED_RECORDS = [
    "2023-10-01 12:00:00,user1,WRITE,/data/fileA.txt",
    "2023-10-01 12:00:00,user1,WRITE,/data/fileB.txt",
    "2023-10-01 12:05:00,user2,READ,/data/fileA.txt",
    "2023-10-01 12:10:00,user1,WRITE,/data/fileB.txt",
    "2023-10-01 12:10:00,user1,WRITE,/data/fileC.txt",
    "2023-10-01 12:10:00,user1,WRITE,/data/fileD.txt",
    "2023-10-01 12:15:00,user3,WRITE,/data/fileB.txt",
    "2023-10-01 12:15:00,user3,WRITE,/data/fileD.txt",
    "2023-10-01 12:20:00,user4,WRITE,/data/fileE.txt",
    "2023-10-01 12:25:00,user2,READ,/data/fileC.txt",
    "2023-10-01 12:25:00,user2,READ,/data/fileE.txt",
    "2023-10-01 12:30:00,user5,WRITE,/data/fileA.txt",
    "2023-10-01 12:30:00,user5,WRITE,/data/fileB.txt",
]


def test_c_parser_exists():
    assert os.path.isfile('/home/user/parser.c'), "C source code /home/user/parser.c does not exist."
    assert os.path.isfile('/home/user/parser'), "Compiled executable /home/user/parser does not exist."
    assert os.access('/home/user/parser', os.X_OK), "/home/user/parser is not executable."


def test_parsed_logs_csv():
    csv_path = '/home/user/parsed_logs.csv'
    assert os.path.isfile(csv_path), f"{csv_path} does not exist."

    with open(csv_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) > 0, f"{csv_path} is empty."
    assert lines[0] == "timestamp,username,action,resource", f"Incorrect header in {csv_path}."
    assert lines[1:] == EXPECTED_RECORDS, f"Parsed records in {csv_path} do not match the expected output."


def test_sqlite_db_exists():
    db_path = '/home/user/audit.db'
    assert os.path.isfile(db_path), f"Database {db_path} does not exist."

    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='logs';")
        table = cursor.fetchone()
        assert table is not None, "Table 'logs' does not exist in the database."
        conn.close()
    except sqlite3.Error as e:
        pytest.fail(f"Failed to connect to SQLite database or query 'logs' table: {e}")


def test_sqlite_rows_and_aggregation():
    expected_rows = [tuple(line.split(',', 3)) for line in EXPECTED_RECORDS]
    conn = sqlite3.connect('/home/user/audit.db')
    try:
        columns = [row[1] for row in conn.execute("PRAGMA table_info(logs)")]
        assert columns == ['timestamp', 'username', 'action', 'resource'], "The logs table has incorrect columns."
        actual_rows = list(conn.execute("SELECT timestamp, username, action, resource FROM logs"))
        assert Counter(actual_rows) == Counter(expected_rows), "The logs table does not contain the normalized CSV records."
        result = list(conn.execute(
            "SELECT resource, COUNT(*) AS count FROM logs "
            "WHERE action = 'WRITE' GROUP BY resource "
            "ORDER BY count DESC, resource ASC LIMIT 3"
        ))
        assert result == [('/data/fileB.txt', 4), ('/data/fileA.txt', 2), ('/data/fileD.txt', 2)], "The database aggregation is incorrect."
    finally:
        conn.close()


def test_top_writes_csv():
    csv_path = '/home/user/top_writes.csv'
    assert os.path.isfile(csv_path), f"{csv_path} does not exist."

    with open(csv_path, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "/data/fileB.txt,4",
        "/data/fileA.txt,2",
        "/data/fileD.txt,2"
    ]
    assert lines == expected_lines, f"Contents of {csv_path} do not match expected top writes."


def test_c_parser_uses_iconv():
    c_source_path = '/home/user/parser.c'
    assert os.path.isfile(c_source_path), f"{c_source_path} does not exist."

    with open(c_source_path, 'r', encoding='utf-8') as f:
        content = f.read()

    assert "iconv" in content, f"C source code {c_source_path} does not appear to use the iconv library."


def build_iconv_tracer():
    source = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <iconv.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void record(const char *message) {
    const char *path = getenv("ICONV_TRACE_FILE");
    if (!path) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        write(fd, message, strlen(message));
        close(fd);
    }
}

iconv_t iconv_open(const char *tocode, const char *fromcode) {
    static iconv_t (*real_open)(const char *, const char *);
    if (!real_open) real_open = dlsym(RTLD_NEXT, "iconv_open");
    char line[512];
    snprintf(line, sizeof(line), "OPEN:%s:%s\n", tocode ? tocode : "", fromcode ? fromcode : "");
    record(line);
    return real_open(tocode, fromcode);
}

size_t iconv(iconv_t cd, char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft) {
    static size_t (*real_iconv)(iconv_t, char **, size_t *, char **, size_t *);
    if (!real_iconv) real_iconv = dlsym(RTLD_NEXT, "iconv");
    record("CONVERT\n");
    return real_iconv(cd, inbuf, inbytesleft, outbuf, outbytesleft);
}

int iconv_close(iconv_t cd) {
    static int (*real_close)(iconv_t);
    if (!real_close) real_close = dlsym(RTLD_NEXT, "iconv_close");
    record("CLOSE\n");
    return real_close(cd);
}
'''
    with open('/tmp/iconv_trace.c', 'w', encoding='utf-8') as f:
        f.write(source)
    result = subprocess.run(
        ['gcc', '-shared', '-fPIC', '/tmp/iconv_trace.c', '-o', '/tmp/iconv_trace.so', '-ldl'],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, f"Could not build iconv call tracer: {result.stderr}"


def exercise_parser(executable, suffix):
    token = secrets.token_hex(10)
    entries = [
        ('2024-02-03 04:05:06', f'josé_{token}', 'WRITE', [f'/srv/alpha_{token}.dat', f'/srv/Ω_{token}.dat']),
        ('2024-02-03 04:06:07', f'user_{token}', 'READ', [f'/srv/space item_{token}.txt']),
        ('2024-02-03 04:07:08', f'naïve_{token}', 'WRITE', [f'/srv/Ω_{token}.dat', f'/srv/final_{token}.bin', f'/srv/三_{token}.log']),
    ]
    text = ''.join(
        f'[{timestamp}] {username} :: {action} -> {";".join(resources)}\n'
        for timestamp, username, action, resources in entries
    )
    with open('/home/user/legacy_audit.log', 'wb') as f:
        f.write(text.encode('utf-16le'))

    trace_path = f'/tmp/iconv_trace_{suffix}.log'
    if os.path.exists(trace_path):
        os.unlink(trace_path)
    env = os.environ.copy()
    env['LD_PRELOAD'] = '/tmp/iconv_trace.so'
    env['ICONV_TRACE_FILE'] = trace_path
    result = subprocess.run(
        [executable], cwd='/home/user', env=env,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, f"Parser failed on a generated UTF-16LE fixture: {result.stderr}"

    expected = [['timestamp', 'username', 'action', 'resource']]
    for timestamp, username, action, resources in entries:
        for resource in resources:
            expected.append([timestamp, username, action, resource])
    with open('/home/user/parsed_logs.csv', 'r', encoding='utf-8', newline='') as f:
        actual = list(csv.reader(f))
    assert actual == expected, "Parser did not correctly normalize a generated UTF-16LE fixture."

    assert os.path.isfile(trace_path), "The parser did not call the iconv library."
    trace = open(trace_path, 'r', encoding='utf-8').read()
    normalized = trace.upper().replace('-', '').replace('_', '')
    assert 'OPEN:UTF8:UTF16LE' in normalized, "The parser did not open an iconv UTF-16LE to UTF-8 conversion."
    assert 'CONVERT' in trace, "The parser did not perform conversion through iconv."


def test_zz_parser_is_real_c_program_and_handles_generated_input():
    with open('/home/user/parser', 'rb') as f:
        assert f.read(4) == b'\x7fELF', "/home/user/parser is not a compiled native executable."

    build_iconv_tracer()
    exercise_parser('/home/user/parser', 'submitted')

    result = subprocess.run(
        ['gcc', '/home/user/parser.c', '-o', '/tmp/recompiled_parser'],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, f"parser.c does not compile with gcc: {result.stderr}"

    symbols = subprocess.run(
        ['nm', '-D', '/tmp/recompiled_parser'], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10, check=True
    ).stdout
    names = {line.split()[-1].split('@')[0] for line in symbols.splitlines() if line.split()}
    assert {'iconv_open', 'iconv', 'iconv_close'} <= names, "The compiled C parser is not linked to the required iconv functions."
    exercise_parser('/tmp/recompiled_parser', 'recompiled')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
