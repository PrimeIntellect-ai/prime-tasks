#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import secrets
import subprocess
import tempfile


def test_audit_report_content():
    report_path = "/home/user/audit_report.txt"
    assert os.path.isfile(report_path), f"File {report_path} is missing."

    expected_output = (
        "U_03,DB_A,EXT_Z,1002,1008\n"
        "U_04,DB_C,EXT_X,1003,1010\n"
        "U_05,DB_A,EXT_W,1004,1005\n"
    )

    with open(report_path, "r") as f:
        content = f.read().strip()

    assert content == expected_output.strip(), f"Content of {report_path} does not match expected output."


def test_c_program_exists_and_compiles():
    c_file = "/home/user/graph_audit.c"
    executable = "/home/user/graph_audit"

    assert os.path.isfile(c_file), f"C source file {c_file} is missing."
    assert os.path.isfile(executable), f"Executable {executable} is missing."
    assert os.access(executable, os.X_OK), f"File {executable} is not executable."

    result = subprocess.run(
        ["gcc", "-O2", "-Wall", "-o", executable, c_file],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"C source did not compile:\n{result.stderr}"
    assert result.stderr.strip() == "", f"C source compiled with warnings:\n{result.stderr}"
    assert os.path.isfile(executable), f"Compiled executable {executable} is missing."
    assert os.access(executable, os.X_OK), f"Compiled file {executable} is not executable."


def test_executable_logic():
    executable = "/home/user/graph_audit"
    csv_file = "/home/user/system_logs.csv"

    # Preserve the original fixed invocation check.
    cmd = [executable, csv_file, "2", "0"]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)

    expected = (
        "U_01,DB_A,EXT_Z,1000,1005\n"
        "U_02,DB_B,EXT_Y,1001,1006\n"
    )

    assert result.returncode == 0, "Executable returned non-zero exit code."
    assert result.stdout.strip() == expected.strip(), "Executable output did not match expected logic for limit 2 offset 0."


def oracle(rows):
    reads = []
    transfers = []
    for timestamp, src, dst, action in rows:
        timestamp = int(timestamp)
        if src.startswith("U_") and dst.startswith("DB_") and action == "READ":
            reads.append((timestamp, src, dst))
        if src.startswith("U_") and dst.startswith("EXT_") and action == "TRANSFER":
            transfers.append((timestamp, src, dst))

    matches = []
    for time1, user, database in reads:
        for time2, transfer_user, endpoint in transfers:
            if transfer_user == user and time2 > time1:
                matches.append((user, database, endpoint, time1, time2))
    matches.sort(key=lambda record: (record[3], record[4]))
    return matches


def format_records(records):
    return "\n".join(
        f"{user},{database},{endpoint},{time1},{time2}"
        for user, database, endpoint, time1, time2 in records
    )


def test_compiled_program_on_unseen_graph_and_pagination():
    executable = "/home/user/graph_audit"
    rng = random.SystemRandom()
    nonce = secrets.token_hex(4).upper()
    rows = []

    # Create multiple users with multiple qualifying edges so the result must be
    # computed as a join rather than copied from the image's fixed data.
    start = rng.randint(20000, 80000)
    for i in range(7):
        user = f"U_{nonce}_{i}"
        base = start + i * 100
        db1 = f"DB_{nonce}_{i}_A"
        db2 = f"DB_{nonce}_{i}_B"
        ext1 = f"EXT_{nonce}_{i}_X"
        ext2 = f"EXT_{nonce}_{i}_Y"
        rows.extend([
            (base + 1, user, db1, "READ"),
            (base + 11, user, db2, "READ"),
            (base + 21, user, ext1, "TRANSFER"),
            (base + 31, user, ext2, "TRANSFER"),
            (base, user, f"EXT_{nonce}_{i}_EARLY", "TRANSFER"),
            (base + 41, user, f"DB_{nonce}_{i}_IGN", "WRITE"),
        ])

    # Strict-time, prefix, action, and same-user decoys.
    eq_user = f"U_{nonce}_EQ"
    eq_time = start + 900
    rows.extend([
        (eq_time, eq_user, f"DB_{nonce}_EQ", "READ"),
        (eq_time, eq_user, f"EXT_{nonce}_EQ", "TRANSFER"),
        (start + 1001, f"X_{nonce}", f"DB_{nonce}_BAD", "READ"),
        (start + 1002, f"X_{nonce}", f"EXT_{nonce}_BAD", "TRANSFER"),
        (start + 1011, f"U_{nonce}_BAD", f"DBX_{nonce}", "READ"),
        (start + 1012, f"U_{nonce}_BAD", f"EXTX_{nonce}", "TRANSFER"),
        (start + 1021, f"U_{nonce}_READONLY", f"DB_{nonce}_ONLY", "READ"),
        (start + 1022, f"U_{nonce}_OTHER", f"EXT_{nonce}_ONLY", "TRANSFER"),
        (start + 1031, f"U_{nonce}_ACT", f"DB_{nonce}_ACT", "read"),
        (start + 1032, f"U_{nonce}_ACT", f"EXT_{nonce}_ACT", "transfer"),
    ])

    rng.shuffle(rows)
    expected_all = oracle(rows)
    assert len(expected_all) > 20

    fd, csv_path = tempfile.mkstemp(prefix="graph_audit_unseen_", suffix=".csv")
    os.close(fd)
    try:
        with open(csv_path, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["timestamp", "src_node", "dst_node", "action"])
            writer.writerows(rows)

        cases = [
            (len(expected_all) + 5, 0),
            (3, 2),
            (7, rng.randint(3, 10)),
            (5, len(expected_all) + 4),
        ]
        for limit, offset in cases:
            result = subprocess.run(
                [executable, csv_path, str(limit), str(offset)],
                capture_output=True,
                text=True,
                timeout=10,
            )
            expected = format_records(expected_all[offset:offset + limit])
            assert result.returncode == 0, (
                f"Executable failed for limit={limit}, offset={offset}: {result.stderr}"
            )
            assert result.stdout.strip() == expected.strip(), (
                f"Wrong result for unseen graph with limit={limit}, offset={offset}.\n"
                f"Expected:\n{expected}\nActual:\n{result.stdout}"
            )
    finally:
        os.unlink(csv_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
