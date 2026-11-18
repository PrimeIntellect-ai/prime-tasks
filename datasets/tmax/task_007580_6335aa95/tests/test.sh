#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import secrets
import sqlite3
import subprocess
import uuid

PROGRAM = "/home/user/process_audit"
SOURCE = "/home/user/process_audit.c"
DB = "/home/user/audit.db"


def run_program(path, limit, offset):
    return subprocess.run(
        [path, str(limit), str(offset)],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_source_file_exists():
    assert os.path.isfile(SOURCE), "The C source file /home/user/process_audit.c is missing."


def test_executable_exists():
    assert os.path.isfile(PROGRAM), "The compiled executable /home/user/process_audit is missing."
    assert os.access(PROGRAM, os.X_OK), "/home/user/process_audit is not executable."
    with open(PROGRAM, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/process_audit is not a compiled ELF executable."
    linked = subprocess.run(["ldd", PROGRAM], capture_output=True, text=True, timeout=10)
    assert linked.returncode == 0, "Unable to inspect the executable's shared-library dependencies."
    assert "libsqlite3" in linked.stdout, "The executable is not linked against libsqlite3."


def test_index_created():
    assert os.path.exists(DB), f"Database file {DB} is missing."

    # Ensure the program itself creates the index rather than relying on one
    # left in the database before verification.
    conn = sqlite3.connect(DB)
    conn.execute("DROP INDEX IF EXISTS idx_audit_aid")
    conn.commit()
    conn.close()

    result = run_program(PROGRAM, 1, 0)
    assert result.returncode == 0, "The program failed while creating idx_audit_aid."

    conn = sqlite3.connect(DB)
    cursor = conn.cursor()
    cursor.execute("SELECT count(*) FROM sqlite_master WHERE type='index' AND name='idx_audit_aid';")
    count = cursor.fetchone()[0]
    cursor.execute("SELECT tbl_name FROM sqlite_master WHERE type='index' AND name='idx_audit_aid'")
    row = cursor.fetchone()
    cursor.execute("PRAGMA index_info('idx_audit_aid')")
    columns = [r[2] for r in cursor.fetchall()]
    conn.close()

    assert count == 1, "The index 'idx_audit_aid' was not created in the database."
    assert row is not None and row[0] == "audit_log", "idx_audit_aid is not an index on audit_log."
    assert columns == ["aid"], f"idx_audit_aid must index exactly audit_log(aid), but indexes {columns}."


def test_program_output_1():
    result = run_program(PROGRAM, 2, 0)
    assert result.returncode == 0, "The program /home/user/process_audit returned a non-zero exit code."

    expected_output = "bob,PublicWeb,InternalPortal,2023-10-01 10:20:00\ncharlie,InternalPortal,CustomerDB,2023-10-01 10:10:00\n"
    actual_output = result.stdout.replace('\r\n', '\n')

    assert actual_output.strip() == expected_output.strip(), f"Output mismatch for limit 2, offset 0.\nExpected:\n{expected_output}\nGot:\n{actual_output}"


def test_program_output_2():
    result = run_program(PROGRAM, 10, 2)
    assert result.returncode == 0, "The program /home/user/process_audit returned a non-zero exit code."

    expected_output = "bob,InternalPortal,CustomerDB,2023-10-01 10:05:00\nalice,PublicWeb,InternalPortal,2023-10-01 10:00:00\n"
    actual_output = result.stdout.replace('\r\n', '\n')

    assert actual_output.strip() == expected_output.strip(), f"Output mismatch for limit 10, offset 2.\nExpected:\n{expected_output}\nGot:\n{actual_output}"


def test_source_builds_and_general_join_pagination_csv():
    rebuilt = f"/tmp/process_audit_rebuilt_{os.getpid()}"
    build = subprocess.run(
        ["gcc", SOURCE, "-o", rebuilt, "-lsqlite3"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f"The submitted C source does not compile with libsqlite3:\n{build.stderr}"
    assert os.access(rebuilt, os.X_OK), "Compiling the submitted source did not produce an executable."
    linked = subprocess.run(["ldd", rebuilt], capture_output=True, text=True, timeout=10)
    assert linked.returncode == 0 and "libsqlite3" in linked.stdout, "The submitted source does not produce a program linked to libsqlite3."

    # Verify that the rebuilt source also creates the required correctly-shaped index.
    conn = sqlite3.connect(DB)
    conn.execute("DROP INDEX IF EXISTS idx_audit_aid")
    conn.commit()
    conn.close()
    creation = run_program(rebuilt, 0, 0)
    assert creation.returncode == 0, "The executable rebuilt from the submitted source failed."

    token = uuid.uuid4().hex
    conn = sqlite3.connect(DB)
    cur = conn.cursor()
    next_uid = cur.execute("SELECT COALESCE(MAX(uid), 0) + 100 FROM users").fetchone()[0]
    next_aid = cur.execute("SELECT COALESCE(MAX(aid), 0) + 100 FROM assets").fetchone()[0]
    next_log = cur.execute("SELECT COALESCE(MAX(log_id), 0) + 100 FROM audit_log").fetchone()[0]

    # Add runtime-unique rows, including commas and quotes that require standard CSV escaping.
    for i in range(9):
        uid = next_uid + i
        source_aid = next_aid + i * 2
        dest_aid = source_aid + 1
        username = f'user,{token[:8]} "{i}"'
        source_name = f'source,{token[8:16]}-{i}'
        dest_name = f'dest "{token[16:24]}"-{i}'
        cur.execute("INSERT INTO users(uid, username, dept) VALUES (?, ?, ?)", (uid, username, "audit"))
        cur.execute("INSERT INTO assets(aid, asset_name, classification_level) VALUES (?, ?, ?)", (source_aid, source_name, i + 1))
        cur.execute("INSERT INTO assets(aid, asset_name, classification_level) VALUES (?, ?, ?)", (dest_aid, dest_name, i + 2))
        cur.execute("INSERT INTO data_flows(source_aid, dest_aid) VALUES (?, ?)", (source_aid, dest_aid))
        cur.execute(
            "INSERT INTO audit_log(log_id, uid, aid, timestamp) VALUES (?, ?, ?, ?)",
            (next_log + i, uid, source_aid, f"2000-01-01 00:00:{8-i:02d}"),
        )

    # Decoys must not qualify: equal classification and a log on a destination asset.
    decoy_source = next_aid + 1000
    decoy_dest = decoy_source + 1
    cur.execute("INSERT INTO assets VALUES (?, ?, ?)", (decoy_source, f"decoy-{token}", 7))
    cur.execute("INSERT INTO assets VALUES (?, ?, ?)", (decoy_dest, f"decoy-dest-{token}", 7))
    cur.execute("INSERT INTO data_flows VALUES (?, ?)", (decoy_source, decoy_dest))
    cur.execute("INSERT INTO audit_log VALUES (?, ?, ?, ?)", (next_log + 1000, next_uid, decoy_source, "2099-01-01 00:00:00"))
    conn.commit()

    oracle_sql = """
        SELECT u.username, a.asset_name, b.asset_name, al.timestamp
        FROM audit_log AS al
        JOIN users AS u ON u.uid = al.uid
        JOIN assets AS a ON a.aid = al.aid
        JOIN data_flows AS df ON df.source_aid = a.aid
        JOIN assets AS b ON b.aid = df.dest_aid
        WHERE b.classification_level > a.classification_level
        ORDER BY al.timestamp DESC, u.username ASC
        LIMIT ? OFFSET ?
    """

    rng = secrets.SystemRandom()
    pages = [(5, 4), (3, 9), (50, 0), (rng.randint(1, 6), rng.randint(4, 11))]
    saw_runtime_row = False
    for limit, offset in pages:
        rows = conn.execute(oracle_sql, (limit, offset)).fetchall()
        output = io.StringIO(newline="")
        writer = csv.writer(output, lineterminator="\n")
        writer.writerows(rows)
        expected = output.getvalue()

        for candidate in (PROGRAM, rebuilt):
            result = run_program(candidate, limit, offset)
            assert result.returncode == 0, f"{candidate} failed for limit={limit}, offset={offset}: {result.stderr}"
            actual = result.stdout.replace("\r\n", "\n")
            assert actual == expected, (
                f"Incorrect join, ordering, pagination, or CSV output for limit={limit}, offset={offset}.\n"
                f"Expected:\n{expected}\nGot:\n{actual}"
            )
            saw_runtime_row = saw_runtime_row or token[:8] in actual

    conn.close()
    assert saw_runtime_row, "The behavioral tests did not exercise the runtime-inserted audit rows."


def test_requires_exactly_two_arguments():
    for args in ([], ["1"], ["1", "0", "extra"]):
        result = subprocess.run([PROGRAM, *args], capture_output=True, text=True, timeout=10)
        assert result.returncode != 0, f"The program must reject argument list: {args}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
