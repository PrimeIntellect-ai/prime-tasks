#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import sqlite3
import subprocess
import tempfile

AGENT_PATH = "/home/user/route_degree"
DB_PATH = "/home/user/routing.db"

AUDIT_SOURCE = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <sqlite3.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void log_stmt(sqlite3_stmt *stmt) {
    const char *path = getenv("ROUTE_DEGREE_AUDIT_LOG");
    if (!path || !stmt) return;
    const char *sql = sqlite3_sql(stmt);
    if (!sql) return;

    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd < 0) return;
    write(fd, "STEP\t", 5);
    for (const char *p = sql; *p; ++p) {
        char c = (*p == '\n' || *p == '\r') ? ' ' : *p;
        write(fd, &c, 1);
    }
    write(fd, "\n", 1);
    close(fd);
}

int sqlite3_step(sqlite3_stmt *stmt) {
    static int (*real_step)(sqlite3_stmt *) = NULL;
    if (!real_step) real_step = dlsym(RTLD_NEXT, "sqlite3_step");
    log_stmt(stmt);
    return real_step(stmt);
}
'''


def build_auditor(tmpdir):
    source = os.path.join(tmpdir, "sqlite_audit.c")
    library = os.path.join(tmpdir, "sqlite_audit.so")
    with open(source, "w") as f:
        f.write(AUDIT_SOURCE)
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", source, "-o", library, "-ldl", "-lsqlite3"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Could not build SQLite audit shim: {result.stderr}"
    return library


def test_agent_executable_exists():
    assert os.path.isfile(AGENT_PATH), (
        f"Agent executable not found at {AGENT_PATH}. Did you compile your C program "
        "to the correct path?"
    )
    assert os.access(AGENT_PATH, os.X_OK), f"Agent file at {AGENT_PATH} is not executable."

    with open(AGENT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "route_degree must be a compiled native executable."

    elf = subprocess.run(["readelf", "-d", AGENT_PATH], capture_output=True, text=True)
    assert elf.returncode == 0, "route_degree is not a valid dynamically linked ELF executable."
    assert re.search(r"NEEDED.*libsqlite3\.so", elf.stdout, re.IGNORECASE), (
        "route_degree must be a compiled program linked to the sqlite3 C library."
    )


def test_fuzz_equivalence_and_full_scan_query():
    rng = secrets.SystemRandom()

    # Add unpredictable data only after the agent has finished. This prevents a fixed
    # mapping for the original tiny fixture from satisfying the behavioral checks.
    dynamic_nodes = rng.sample(range(100000, 2000000000), 24)
    with sqlite3.connect(DB_PATH) as db:
        for src in dynamic_nodes:
            for _ in range(rng.randint(1, 9)):
                db.execute(
                    "INSERT INTO routes(src, dst) VALUES (?, ?)",
                    (src, rng.randrange(1, 2000000000)),
                )
        db.commit()

    inputs = [rng.randint(0, 100) for _ in range(40)]
    for node in [14, 27, 55, 91] + dynamic_nodes:
        if node not in inputs:
            inputs.append(node)

    with tempfile.TemporaryDirectory() as tmpdir:
        audit_library = build_auditor(tmpdir)
        audit_log = os.path.join(tmpdir, "sqlite_steps.log")
        env = os.environ.copy()
        env["LD_PRELOAD"] = audit_library
        env["ROUTE_DEGREE_AUDIT_LOG"] = audit_log

        with sqlite3.connect(DB_PATH) as db:
            for val in inputs:
                expected = db.execute(
                    "SELECT count(*) FROM routes NOT INDEXED WHERE src = ?", (val,)
                ).fetchone()[0]

                try:
                    result = subprocess.run(
                        [AGENT_PATH, str(val)],
                        capture_output=True,
                        text=True,
                        timeout=2,
                        env=env,
                        check=True,
                    )
                except subprocess.CalledProcessError as e:
                    raise AssertionError(
                        f"Agent program failed on input {val}: {e.stderr}"
                    ) from e
                except subprocess.TimeoutExpired as e:
                    raise AssertionError(f"Agent timed out on input {val}") from e

                assert re.fullmatch(r"[0-9]+\n?", result.stdout), (
                    f"Output for {val} must contain only one integer, got {result.stdout!r}"
                )
                assert result.stdout.strip() == str(expected), (
                    f"Output mismatch on input {val}. Expected {expected!r}, "
                    f"got {result.stdout.strip()!r}."
                )

        assert os.path.isfile(audit_log), "No executed SQLite statements were observed."
        with open(audit_log, "r", errors="replace") as f:
            statements = f.read()

        assert re.search(
            r"^STEP\t[^\n]*\bFROM\s+routes\s+NOT\s+INDEXED\b[^\n]*$",
            statements,
            re.IGNORECASE | re.MULTILINE,
        ), (
            "The executable must actually execute a query against routes using "
            "NOT INDEXED so the corrupted idx_src index is bypassed."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
