#!/bin/bash
set -e
mkdir -p /logs/verifier

BEHAVIOR_CHECK=/tmp/verifier_get_critical_events.go
trap 'rm -f "$BEHAVIOR_CHECK" /tmp/test_final_state.py' EXIT

cat << 'GO_EOF' > "$BEHAVIOR_CHECK"
package main

import (
    "database/sql"
    "fmt"
    "os"

    storedb "forensic_service/db"
    "forensic_service/models"
    _ "github.com/mattn/go-sqlite3"
)

func fail(format string, args ...interface{}) {
    fmt.Fprintf(os.Stderr, format+"\n", args...)
    os.Exit(1)
}

func main() {
    database, err := sql.Open("sqlite3", ":memory:")
    if err != nil {
        fail("opening database: %v", err)
    }
    defer database.Close()

    _, err = database.Exec(`CREATE TABLE events (
        id INTEGER PRIMARY KEY,
        username TEXT,
        action TEXT,
        severity INTEGER
    )`)
    if err != nil {
        fail("creating events table: %v", err)
    }

    rows := []struct {
        id       int
        username string
        action   string
        severity int
    }{
        {1, "alice", "LOGIN", 1},
        {2, "bob", "UNAUTHORIZED_ACCESS", 5},
        {3, "eve", "DATA_EXFILTRATION", 5},
    }
    for _, row := range rows {
        if _, err := database.Exec(
            "INSERT INTO events (id, username, action, severity) VALUES (?, ?, ?, ?)",
            row.id, row.username, row.action, row.severity,
        ); err != nil {
            fail("inserting row %d: %v", row.id, err)
        }
    }

    store := storedb.NewSQLiteStore(database)
    var audit models.AuditStore = store
    events, err := audit.GetCriticalEvents()
    if err != nil {
        fail("GetCriticalEvents returned an error: %v", err)
    }
    if len(events) != 2 {
        fail("GetCriticalEvents returned %d events; want 2", len(events))
    }

    expected := []models.Event{
        {ID: 2, Username: "bob", Action: "UNAUTHORIZED_ACCESS", Severity: 5},
        {ID: 3, Username: "eve", Action: "DATA_EXFILTRATION", Severity: 5},
    }
    for i := range expected {
        if events[i] != expected[i] {
            fail("event %d = %#v; want %#v", i, events[i], expected[i])
        }
    }
}
GO_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess

SERVICE_DIR = "/home/user/forensic_service"
BEHAVIOR_CHECK = "/tmp/verifier_get_critical_events.go"


def run(command):
    return subprocess.run(
        command,
        cwd=SERVICE_DIR,
        capture_output=True,
        text=True,
    )


def test_compilation_succeeds():
    """Verify that the project successfully compiles after fixing the interface mismatch."""
    res = run(["go", "build", "./..."])
    assert res.returncode == 0, f"Project fails to compile. Output:\n{res.stderr}"


def test_tests_pass():
    """Verify that all tests, including the newly added regression test, pass."""
    res = run(["go", "test", "./..."])
    assert res.returncode == 0, f"Tests fail. Output:\n{res.stdout}\n{res.stderr}"


def test_get_critical_events_known_rows():
    """Independently execute GetCriticalEvents against verifier-created rows."""
    res = run(["go", "run", BEHAVIOR_CHECK])
    assert res.returncode == 0, (
        "GetCriticalEvents failed the independent database check. "
        f"Output:\n{res.stdout}\n{res.stderr}"
    )


def test_db_go_modifications():
    """Verify that db.go has been fixed correctly."""
    db_path = os.path.join(SERVICE_DIR, "db", "db.go")
    assert os.path.exists(db_path), f"{db_path} does not exist."

    with open(db_path, "r") as f:
        db_content = f.read()

    assert "[]*models.Event" not in db_content, "Interface signature mismatch (returning pointers) not fixed properly in db.go."
    assert "[]models.Event" in db_content, "GetCriticalEvents should return []models.Event."
    assert "&ev.Action, &ev.Username" not in db_content, "Row scanning bug (swapped Action and Username) not fixed in db.go."


def test_db_test_go_exists_and_content():
    """Verify that db_test.go exists and contains the required regression test."""
    test_file = os.path.join(SERVICE_DIR, "db", "db_test.go")
    assert os.path.exists(test_file), f"{test_file} does not exist."

    with open(test_file, "r") as f:
        test_content = f.read()

    assert "TestGetCriticalEvents" in test_content, "TestGetCriticalEvents function missing in db_test.go."
    assert "UNAUTHORIZED_ACCESS" in test_content, "Test does not contain required test data (UNAUTHORIZED_ACCESS)."
    assert "bob" in test_content, "Test does not contain required test data (bob)."
    assert "alice" in test_content, "Test does not contain required test data (alice)."
    assert "eve" in test_content, "Test does not contain required test data (eve)."

    res = run(["go", "test", "./db", "-list", "^TestGetCriticalEvents$"])
    assert res.returncode == 0, f"Unable to enumerate db tests:\n{res.stdout}\n{res.stderr}"
    assert "TestGetCriticalEvents" in res.stdout.splitlines(), (
        "db_test.go does not define an executable TestGetCriticalEvents test."
    )


def test_fix_report_log():
    """Verify that the fix report has exactly the required four-line format."""
    log_file = os.path.join(SERVICE_DIR, "fix_report.log")
    assert os.path.exists(log_file), f"{log_file} does not exist."

    with open(log_file, "r") as f:
        log_content = f.read()

    assert "STATUS: FIXED" in log_content, "fix_report.log missing 'STATUS: FIXED'."
    assert "TEST_PASSED: TRUE" in log_content, "fix_report.log missing 'TEST_PASSED: TRUE'."
    assert "COMPILER_ISSUE_ROOT_CAUSE:" in log_content, "fix_report.log missing 'COMPILER_ISSUE_ROOT_CAUSE:'."
    assert "QUERY_ISSUE_ROOT_CAUSE:" in log_content, "fix_report.log missing 'QUERY_ISSUE_ROOT_CAUSE:'."

    lines = log_content.splitlines()
    assert len(lines) == 4, "fix_report.log must contain exactly four lines with no extra content."
    assert lines[0] == "STATUS: FIXED", "The first report line must be exactly 'STATUS: FIXED'."
    assert lines[1].startswith("COMPILER_ISSUE_ROOT_CAUSE:"), "Invalid compiler root-cause line."
    assert lines[1][len("COMPILER_ISSUE_ROOT_CAUSE:"):].strip(), "Compiler root-cause explanation is empty."
    assert lines[2].startswith("QUERY_ISSUE_ROOT_CAUSE:"), "Invalid query root-cause line."
    assert lines[2][len("QUERY_ISSUE_ROOT_CAUSE:"):].strip(), "Query root-cause explanation is empty."
    assert lines[3] == "TEST_PASSED: TRUE", "The final report line must be exactly 'TEST_PASSED: TRUE'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
