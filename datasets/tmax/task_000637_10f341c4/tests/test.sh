#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
import stat
import subprocess

REPO_DIR = "/home/user/pipeline_repo"
OUTPUT_TXT = os.path.join(REPO_DIR, "output.txt")
INIT_SQL = os.path.join(REPO_DIR, "init.sql")
PROCESS_SH = os.path.join(REPO_DIR, "process.sh")

EXPECTED_TOKEN = "sec_9948_aB2"
EXPECTED_PROCESS = '''#!/bin/bash
TOKEN=$1

if [ -z "$TOKEN" ]; then
    echo "Error: Token required"
    exit 1
fi

rm -f data.db
sqlite3 data.db < init.sql

if [ $? -ne 0 ]; then
    echo "Database build failed"
    exit 1
fi

# TOKEN WAS REMOVED FROM BELOW
if [ "$TOKEN" == "sec_9948_aB2" ]; then
    sqlite3 data.db "SELECT metric_name, value FROM metrics WHERE metric_name='revenue';" > output.txt
else
    echo "Invalid token"
    exit 1
fi
'''


def run(cmd, **kwargs):
    return subprocess.run(cmd, cwd=REPO_DIR, capture_output=True, text=True,
                          timeout=10, **kwargs)


def recover_token_from_history():
    roots = run(["git", "rev-list", "--max-parents=0", "HEAD"])
    assert roots.returncode == 0, roots.stderr
    root_commits = roots.stdout.split()
    assert len(root_commits) == 1, "Repository must retain its original history."

    historical = run(["git", "show", f"{root_commits[0]}:process.sh"])
    assert historical.returncode == 0, historical.stderr
    matches = re.findall(r'if \[ "\$TOKEN" == "(sec_[A-Za-z0-9_]+)" \]; then', historical.stdout)
    assert len(matches) == 1, "Could not uniquely recover the removed token from Git history."
    return matches[0]


def test_init_sql_fixed():
    """Verify that the SQL dump has been fixed."""
    assert os.path.isfile(INIT_SQL), f"{INIT_SQL} is missing."
    with open(INIT_SQL, "r") as f:
        content = f.read()
    assert "INZERT" not in content, "init.sql still contains the corrupted 'INZERT' syntax."
    assert "INSERT INTO metrics" in content, "init.sql does not contain valid 'INSERT' statements."

    db = sqlite3.connect(":memory:")
    try:
        db.executescript(content)
        schema = db.execute("PRAGMA table_info(metrics)").fetchall()
        assert schema == [
            (0, "id", "INTEGER", 0, None, 1),
            (1, "metric_name", "TEXT", 0, None, 0),
            (2, "value", "TEXT", 0, None, 0),
        ], f"The metrics schema was changed: {schema!r}"
        rows = db.execute(
            "SELECT id, metric_name, value FROM metrics ORDER BY id"
        ).fetchall()
        assert rows == [
            (1, "user_count", "1042"),
            (2, "revenue", "9984.50"),
            (3, "active_sessions", "342"),
        ], f"The initialized metric data was changed: {rows!r}"
        objects = db.execute(
            "SELECT type, name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"
        ).fetchall()
        assert objects == [("table", "metrics")], f"Unexpected database objects: {objects!r}"
    finally:
        db.close()


def test_process_sh_syntax_fixed():
    """Verify that the bash script no longer has syntax errors."""
    assert os.path.isfile(PROCESS_SH), f"{PROCESS_SH} is missing."
    assert stat.S_ISREG(os.lstat(PROCESS_SH).st_mode), "process.sh must be a regular file."
    result = subprocess.run(["bash", "-n", PROCESS_SH], capture_output=True, text=True)
    assert result.returncode == 0, f"process.sh still has syntax errors:\n{result.stderr}"
    assert os.access(PROCESS_SH, os.X_OK), "process.sh is not executable."


def test_history_and_process_logic_preserved():
    token = recover_token_from_history()
    assert token == EXPECTED_TOKEN, "The original Git history or recovered token was altered."
    with open(PROCESS_SH, "r") as f:
        content = f.read()
    assert content == EXPECTED_PROCESS, (
        "process.sh must retain its original logic; only the missing fi and recovered token should be restored."
    )


def test_pipeline_executes_with_recovered_token():
    token = recover_token_from_history()

    for path in (OUTPUT_TXT, os.path.join(REPO_DIR, "data.db")):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    missing = run(["./process.sh"])
    assert missing.returncode != 0, "process.sh must reject a missing token."

    try:
        os.remove(OUTPUT_TXT)
    except FileNotFoundError:
        pass
    invalid = run(["./process.sh", token + "_invalid"])
    assert invalid.returncode != 0, "process.sh must reject an invalid token."
    assert not os.path.exists(OUTPUT_TXT), "An invalid token must not generate output.txt."

    valid = run(["./process.sh", token])
    assert valid.returncode == 0, (
        f"Pipeline failed with the recovered token.\nstdout:\n{valid.stdout}\nstderr:\n{valid.stderr}"
    )


def test_output_txt_correct():
    """Verify that the pipeline ran successfully and produced the correct output."""
    assert os.path.isfile(OUTPUT_TXT), f"{OUTPUT_TXT} was not generated. Did the script run successfully?"
    with open(OUTPUT_TXT, "r") as f:
        content = f.read().strip()
    expected_output = "revenue|9984.50"
    assert content == expected_output, f"output.txt contains incorrect data. Expected '{expected_output}', got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
