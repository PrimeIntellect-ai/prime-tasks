#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import heapq
import os
import random
import shutil
import sqlite3
import stat
import subprocess
import tempfile

SOLUTION_PATH = "/home/user/solution.txt"
SCRIPT_PATH = "/home/user/solve.py"
DB_PATH = "/home/user/backups.db"
EXPECTED_OUTPUT = "PATH: ROOT->A->B->LEAF | DURATION: 35"


def test_solution_file_exists():
    assert os.path.isfile(SOLUTION_PATH), f"Solution file not found at {SOLUTION_PATH}"


def test_solution_content():
    with open(SOLUTION_PATH, "r") as f:
        content = f.read().strip()

    assert content == EXPECTED_OUTPUT, f"Expected '{EXPECTED_OUTPUT}', but got '{content}'"


def remove_path(path):
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    elif os.path.lexists(path):
        os.remove(path)


def create_database(jobs, deps):
    remove_path(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('CREATE TABLE jobs (job_name TEXT PRIMARY KEY, duration INTEGER)')
        conn.execute('CREATE TABLE job_deps (parent_job TEXT, child_job TEXT)')
        conn.executemany('INSERT INTO jobs VALUES (?, ?)', jobs)
        conn.executemany('INSERT INTO job_deps VALUES (?, ?)', deps)
        conn.execute('CREATE INDEX idx_dep_parent ON job_deps(parent_job)')
        conn.commit()
    finally:
        conn.close()


def expected_result(jobs, deps):
    durations = dict(jobs)
    adjacency = {}
    for parent, child in deps:
        adjacency.setdefault(parent, []).append(child)

    queue = [(durations['ROOT'], ('ROOT',), 'ROOT')]
    best = {}
    while queue:
        total, path, node = heapq.heappop(queue)
        if node in best and best[node] <= total:
            continue
        best[node] = total
        if node == 'LEAF':
            return f"PATH: {'->'.join(path)} | DURATION: {total}"
        for child in adjacency.get(node, []):
            if child not in path:
                heapq.heappush(queue, (total + durations[child], path + (child,), child))
    raise AssertionError("Verifier fixture has no ROOT-to-LEAF path")


def run_submission(expected):
    trace_fd, trace_path = tempfile.mkstemp(prefix="sqlite_trace_", text=True)
    os.close(trace_fd)
    hook_dir = tempfile.mkdtemp(prefix="sqlite_hook_")
    try:
        with open(os.path.join(hook_dir, "sitecustomize.py"), "w") as f:
            f.write(r'''import os
import sqlite3
_real_connect = sqlite3.connect
_trace_path = os.environ.get("VERIFIER_SQL_TRACE")
def _tracked_connect(*args, **kwargs):
    connection = _real_connect(*args, **kwargs)
    if _trace_path:
        def _record(statement):
            with open(_trace_path, "a", encoding="utf-8") as out:
                out.write(statement.replace("\n", " ") + "\n--END--\n")
        connection.set_trace_callback(_record)
    return connection
sqlite3.connect = _tracked_connect
''')

        env = os.environ.copy()
        old_pythonpath = env.get("PYTHONPATH")
        env["PYTHONPATH"] = hook_dir if not old_pythonpath else hook_dir + os.pathsep + old_pythonpath
        env["VERIFIER_SQL_TRACE"] = trace_path
        completed = subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert completed.returncode == 0, (
            f"solve.py exited with status {completed.returncode}. "
            f"stdout: {completed.stdout!r}; stderr: {completed.stderr!r}"
        )
        assert os.path.isfile(SOLUTION_PATH), f"Solution file not found at {SOLUTION_PATH}"
        with open(SOLUTION_PATH, "r") as f:
            actual = f.read().strip()
        assert actual == expected, f"Expected '{expected}', but got '{actual}'"

        with open(trace_path, "r", encoding="utf-8") as f:
            trace = " ".join(f.read().upper().split())
        assert "WITH RECURSIVE" in trace, "solve.py did not execute a Recursive CTE"
        assert "JOBS" in trace and "JOB_DEPS" in trace, (
            "The executed Recursive CTE did not operate on the job hierarchy tables"
        )
        assert (
            "SQLITE_MASTER" in trace
            or "SQLITE_SCHEMA" in trace
            or ("PRAGMA" in trace and ("TABLE_INFO" in trace or "TABLE_XINFO" in trace))
        ), "solve.py did not inspect SQLite schema metadata"
        assert "DROP INDEX" in trace or "NOT INDEXED" in trace, (
            "solve.py neither dropped nor explicitly bypassed the dependency index"
        )
    finally:
        shutil.rmtree(hook_dir, ignore_errors=True)
        remove_path(trace_path)


def main():
    assert os.path.exists(SCRIPT_PATH), f"Python script not found at {SCRIPT_PATH}"
    assert stat.S_ISREG(os.lstat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} is not a regular file"

    backup_fd, backup_path = tempfile.mkstemp(prefix="backups_original_", suffix=".db")
    os.close(backup_fd)
    shutil.copy2(DB_PATH, backup_path)
    try:
        original_jobs = [
            ('ROOT', 0), ('A', 10), ('B', 10), ('C', 5),
            ('D', 20), ('LEAF', 15), ('E', 50),
        ]
        original_deps = [
            ('ROOT', 'A'), ('ROOT', 'C'), ('A', 'B'), ('B', 'LEAF'),
            ('C', 'D'), ('D', 'LEAF'), ('ROOT', 'E'), ('E', 'LEAF'),
        ]
        create_database(original_jobs, original_deps)
        run_submission(EXPECTED_OUTPUT)

        # Preserve the original verifier's file and exact-content assertions.
        test_solution_file_exists()
        test_solution_content()

        rng = random.SystemRandom()
        dynamic_jobs = [
            ('ROOT', 0),
            ('ALPHA', rng.randrange(2, 18)),
            ('BETA', rng.randrange(2, 18)),
            ('GAMMA', rng.randrange(20, 35)),
            ('DELTA', rng.randrange(2, 18)),
            ('OMEGA', rng.randrange(35, 55)),
            ('LEAF', rng.randrange(3, 20)),
        ]
        dynamic_deps = [
            ('ROOT', 'ALPHA'), ('ALPHA', 'BETA'), ('BETA', 'LEAF'),
            ('ROOT', 'GAMMA'), ('GAMMA', 'LEAF'),
            ('ROOT', 'DELTA'), ('DELTA', 'OMEGA'), ('OMEGA', 'LEAF'),
            ('ALPHA', 'OMEGA'),
        ]
        create_database(dynamic_jobs, dynamic_deps)
        run_submission(expected_result(dynamic_jobs, dynamic_deps))
    finally:
        remove_path(DB_PATH)
        shutil.move(backup_path, DB_PATH)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
