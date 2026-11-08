#!/bin/bash
set -e
mkdir -p /logs/verifier

SQLITE_REAL=/usr/bin/sqlite3.verifier-real
SQLITE_LOG=/tmp/sqlite-verifier.log

cleanup() {
    if [ -e "$SQLITE_REAL" ]; then
        rm -f /usr/bin/sqlite3
        mv "$SQLITE_REAL" /usr/bin/sqlite3
    fi
}
trap cleanup EXIT

mv /usr/bin/sqlite3 "$SQLITE_REAL"
cat <<'WRAPPER_EOF' > /usr/bin/sqlite3
#!/bin/bash
tmp=$(mktemp)
cat > "$tmp"
{
    printf 'ARGS: '
    printf '%q ' "$@"
    printf '\nSTDIN:\n'
    cat "$tmp"
    printf '\nEND\n'
} >> /tmp/sqlite-verifier.log
/usr/bin/sqlite3.verifier-real "$@" < "$tmp"
status=$?
rm -f "$tmp"
exit $status
WRAPPER_EOF
chmod 755 /usr/bin/sqlite3
: > "$SQLITE_LOG"
chmod 666 "$SQLITE_LOG"

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import sqlite3
import subprocess
from collections import Counter, defaultdict

RAW_PATH = "/home/user/raw_logs.txt"
CSV_PATH = "/home/user/processed.csv"
DB_PATH = "/home/user/stats.db"
SQLITE_LOG = "/tmp/sqlite-verifier.log"

ORIGINAL_RAW = """2023-11-01T12:00:00Z|user_alpha|System is booting up, system is ready!
2023-11-01T12:01:00Z|user_beta|Warning: low memory. Warning: high CPU!
2023-11-01T12:02:00Z|user_alpha|Ready for processing.
2023-11-01T12:03:00Z|user_gamma|ERROR 404 - Not found. ERROR 500.
2023-11-01T12:04:00Z|user_beta|Memory freed.
"""

ORIGINAL_EXPECTED = [
    ("user_alpha", "is", 2),
    ("user_alpha", "ready", 2),
    ("user_alpha", "system", 2),
    ("user_alpha", "booting", 1),
    ("user_alpha", "for", 1),
    ("user_alpha", "processing", 1),
    ("user_alpha", "up", 1),
    ("user_beta", "memory", 2),
    ("user_beta", "warning", 2),
    ("user_beta", "cpu", 1),
    ("user_beta", "freed", 1),
    ("user_beta", "high", 1),
    ("user_beta", "low", 1),
    ("user_gamma", "error", 2),
    ("user_gamma", "404", 1),
    ("user_gamma", "500", 1),
    ("user_gamma", "found", 1),
    ("user_gamma", "not", 1),
]


def expected_from_raw(raw):
    counts = defaultdict(Counter)
    for line in raw.splitlines():
        if not line:
            continue
        timestamp, user_id, message = line.split("|", 2)
        for token in message.split():
            word = re.sub(r"^[^A-Za-z0-9]+", "", token)
            word = re.sub(r"[^A-Za-z0-9]+$", "", word).lower()
            if word:
                counts[user_id][word] += 1
    rows = []
    for user_id, words in counts.items():
        for word, frequency in words.items():
            rows.append((user_id, word, frequency))
    return sorted(rows, key=lambda row: (row[0], -row[2], row[1]))


def write_raw(raw):
    with open(RAW_PATH, "w", encoding="utf-8", newline="") as f:
        f.write(raw)
    os.chown(RAW_PATH, 1000, 1000)


def read_csv_rows():
    assert os.path.isfile(CSV_PATH), f"{CSV_PATH} was not created as a file."
    rows = []
    with open(CSV_PATH, "r", encoding="utf-8", newline="") as f:
        for row in csv.reader(f):
            if not row:
                continue
            assert len(row) == 3, f"CSV row does not have 3 columns: {row}"
            rows.append((row[0], row[1], int(row[2])))
    return rows


def assert_database(expected):
    assert os.path.isfile(DB_PATH), f"{DB_PATH} was not created as a file."
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='word_stats';")
        assert cursor.fetchone() is not None, "Table 'word_stats' does not exist in the database."
        cursor.execute("PRAGMA table_info(word_stats)")
        schema = [(row[1], row[2].upper()) for row in cursor.fetchall()]
        assert schema == [("user_id", "TEXT"), ("word", "TEXT"), ("frequency", "INTEGER")], schema
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='old_sentinel'")
        assert cursor.fetchone() is None, "etl.sh did not remove the pre-existing database."
        cursor.execute("SELECT user_id, word, frequency FROM word_stats ORDER BY user_id ASC, frequency DESC, word ASC")
        rows = cursor.fetchall()
    finally:
        conn.close()
    assert rows == expected, f"Database records do not match expected sorted data. Got: {rows}"


def prepare_old_database():
    try:
        os.remove(DB_PATH)
    except FileNotFoundError:
        pass
    conn = sqlite3.connect(DB_PATH)
    conn.execute("CREATE TABLE old_sentinel(value TEXT)")
    conn.execute("INSERT INTO old_sentinel VALUES ('must disappear')")
    conn.commit()
    conn.close()


def assert_bulk_import_was_used():
    with open(SQLITE_LOG, "r", encoding="utf-8", errors="replace") as f:
        invocation = f.read().lower()
    assert ".import" in invocation, "etl.sh did not execute SQLite's .import bulk-import command."
    assert "/home/user/processed.csv" in invocation, "SQLite bulk import did not directly use processed.csv."
    assert "word_stats" in invocation, "SQLite bulk import did not target word_stats."
    csv_mode = ".mode csv" in invocation or "--csv" in invocation or re.search(r"(^|\s)-csv(\s|$)", invocation)
    assert csv_mode, "SQLite was not placed in CSV mode for the bulk import."


def run_etl_and_check(expected):
    prepare_old_database()
    open(SQLITE_LOG, "w").close()
    os.chmod(SQLITE_LOG, 0o666)
    result = subprocess.run(
        ["su", "-s", "/bin/bash", "user", "-c", "/home/user/etl.sh"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"etl.sh failed to execute. stdout={result.stdout!r} stderr={result.stderr!r}"
    assert read_csv_rows() == expected, "CSV contents do not match expected sorted data."
    assert_database(expected)
    assert_bulk_import_was_used()


def test_crontab_entry():
    result = subprocess.run(["crontab", "-l", "-u", "user"], capture_output=True, text=True)
    assert result.returncode == 0, "The user crontab is missing."
    found = False
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 6:
            minute, hour, dom, month, dow = parts[:5]
            cmd = " ".join(parts[5:])
            if minute == "15" and hour == "3" and dom == "*" and month == "*" and dow == "1" and "/home/user/etl.sh" in cmd:
                found = True
                break
    assert found, "Crontab entry for /home/user/etl.sh at 3:15 AM every Monday is missing or incorrect."


def test_scripts_exist_and_etl_is_executable():
    assert os.path.isfile("/home/user/process.py"), "/home/user/process.py does not exist as a regular file."
    assert os.path.isfile("/home/user/etl.sh"), "/home/user/etl.sh does not exist as a regular file."
    assert os.access("/home/user/etl.sh", os.X_OK), "/home/user/etl.sh is not executable."
    with open("/home/user/etl.sh", "r", encoding="utf-8", errors="replace") as f:
        etl_source = f.read()
    assert "/home/user/process.py" in etl_source, "etl.sh does not invoke /home/user/process.py."


def test_pipeline_on_original_and_unpredictable_inputs():
    write_raw(ORIGINAL_RAW)
    run_etl_and_check(ORIGINAL_EXPECTED)

    nonce = secrets.token_hex(6)
    user_a = "acct_a_" + nonce
    user_b = "acct_b_" + nonce
    word_a = "mix" + secrets.token_hex(4)
    word_b = "edge" + secrets.token_hex(4)
    random_raw_for_process = (
        f"2026-01-01T00:00:00Z|{user_b}|!!!{word_a.upper()}??? {word_b}, {word_a}\n"
        f"2026-01-01T00:00:01Z|{user_a}|({word_b}) --- co-op... 123!\n"
        f"2026-01-01T00:00:02Z|{user_b}|{word_b} {word_b}; pipe|inside\n"
    )
    process_expected = expected_from_raw(random_raw_for_process)
    write_raw(random_raw_for_process)
    result = subprocess.run(
        ["su", "-s", "/bin/bash", "user", "-c", "python3 /home/user/process.py"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"process.py failed. stdout={result.stdout!r} stderr={result.stderr!r}"
    assert read_csv_rows() == process_expected, "process.py failed on an unpredictable input fixture."

    next_word = "fresh" + secrets.token_hex(5)
    random_raw_for_etl = (
        f"2026-02-02T03:04:05Z|{user_a}|***{next_word.upper()}*** {next_word} end-to-end!\n"
        f"2026-02-02T03:04:06Z|{user_b}|[z9] [z9] [z9] {word_a}.\n"
        f"2026-02-02T03:04:07Z|{user_a}|... 42??? end-to-end\n"
    )
    etl_expected = expected_from_raw(random_raw_for_etl)
    write_raw(random_raw_for_etl)
    with open(CSV_PATH, "w", encoding="utf-8") as f:
        f.write("bogus,stale,999\n")
    run_etl_and_check(etl_expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
