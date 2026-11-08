#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import collections
import csv
import json
import os
import pwd
import random
import shutil
import sqlite3
import subprocess
import tempfile


def test_virtual_environment_exists():
    venv_python = "/home/user/venv/bin/python"
    requirements = "/home/user/requirements.txt"
    assert os.path.isfile(venv_python), f"Virtual environment Python not found at {venv_python}. Did you create the venv?"
    assert os.path.isfile("/home/user/venv/pyvenv.cfg"), "venv/pyvenv.cfg is missing"
    assert os.path.isfile(requirements), f"Requirements file missing at {requirements}"

    # Preserve the original import check.
    result = subprocess.run([venv_python, "-c", "import requests"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to import 'requests' in the virtual environment. Dependencies might not be resolved correctly."

    check_code = r'''
import importlib.metadata
import json
import os
import sys
from pip._vendor.packaging.requirements import Requirement

req_path = "/home/user/requirements.txt"
requirements = []
for raw in open(req_path, encoding="utf-8"):
    line = raw.split("#", 1)[0].strip()
    if line:
        requirements.append(Requirement(line))

names = {r.name.lower().replace("_", "-") for r in requirements}
assert "requests" in names and "urllib3" in names
for req in requirements:
    version = importlib.metadata.version(req.name)
    assert not req.specifier or req.specifier.contains(version, prereleases=True), (req, version)

print(json.dumps({
    "prefix": os.path.realpath(sys.prefix),
    "base_prefix": os.path.realpath(sys.base_prefix),
    "names": sorted(names),
}))
'''
    result = subprocess.run([venv_python, "-c", check_code], capture_output=True, text=True)
    assert result.returncode == 0, f"Installed packages do not satisfy requirements.txt: {result.stderr}"
    info = json.loads(result.stdout)
    assert info["prefix"] == os.path.realpath("/home/user/venv"), "venv Python is not running from the requested virtual environment"
    assert info["base_prefix"] != info["prefix"], "The requested path is not a real Python virtual environment"

    result = subprocess.run([venv_python, "-m", "pip", "check"], capture_output=True, text=True)
    assert result.returncode == 0, f"Dependency conflicts remain in the virtual environment: {result.stdout}{result.stderr}"


def test_database_recovery():
    csv_path = "/home/user/recovered_events.csv"
    assert os.path.isfile(csv_path), f"Recovered events CSV not found at {csv_path}"

    with open(csv_path, "r", encoding="utf-8", newline="") as f:
        rows = list(csv.reader(f))

    # Preserve the original structural assertions.
    assert len(rows) >= 5, f"Expected at least 5 rows in {csv_path}, found {len(rows)}"
    for row in rows:
        if row == ["id", "timestamp", "event_name"]:
            continue
        assert len(row) == 3, f"Expected 3 columns in CSV row, but got: {row}"

    expected = [
        ("1", "1600000000", "event_1"),
        ("2", "1600000001", "event_2"),
        ("3", "1600000002", "event_3"),
        ("4", "1600000003", "event_4"),
        ("5", "1600000004", "event_5"),
    ]
    data_rows = [tuple(row) for row in rows if row != ["id", "timestamp", "event_name"]]
    assert collections.Counter(data_rows) == collections.Counter(expected), \
        f"CSV does not contain exactly the five events recovered from the WAL: {data_rows}"

    # The database itself must also have been recovered, not merely replaced by a fabricated CSV.
    db_path = "/home/user/data/events.db"
    assert os.path.isfile(db_path), f"Recovered database missing at {db_path}"
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        integrity = conn.execute("PRAGMA integrity_check").fetchone()[0]
        db_rows = conn.execute(
            "SELECT id, timestamp, event_name FROM events ORDER BY id"
        ).fetchall()
        conn.close()
    except sqlite3.DatabaseError as exc:
        raise AssertionError(f"Recovered database is not readable: {exc}")
    assert integrity == "ok", f"Recovered database failed integrity_check: {integrity}"
    assert db_rows == [(int(a), int(b), c) for a, b, c in expected], \
        f"Recovered database has incorrect event rows: {db_rows}"


def _install_exec_guard(guard_dir):
    os.makedirs(guard_dir, mode=0o755, exist_ok=True)
    sitecustomize = r'''
import ctypes
import errno

class SockFilter(ctypes.Structure):
    _fields_ = [("code", ctypes.c_ushort), ("jt", ctypes.c_ubyte),
                ("jf", ctypes.c_ubyte), ("k", ctypes.c_uint)]
class SockFprog(ctypes.Structure):
    _fields_ = [("len", ctypes.c_ushort), ("filter", ctypes.POINTER(SockFilter))]

# x86-64 seccomp filter: deny execve and execveat after Python has started.
flt = (SockFilter * 6)(
    SockFilter(0x20, 0, 0, 0),
    SockFilter(0x15, 0, 1, 59),
    SockFilter(0x06, 0, 0, 0x00050000 | errno.EPERM),
    SockFilter(0x15, 0, 1, 322),
    SockFilter(0x06, 0, 0, 0x00050000 | errno.EPERM),
    SockFilter(0x06, 0, 0, 0x7fff0000),
)
prog = SockFprog(len(flt), flt)
libc = ctypes.CDLL(None, use_errno=True)
if libc.prctl(38, 1, 0, 0, 0) != 0:
    raise OSError(ctypes.get_errno(), "PR_SET_NO_NEW_PRIVS failed")
if libc.prctl(22, 2, ctypes.byref(prog), 0, 0) != 0:
    raise OSError(ctypes.get_errno(), "PR_SET_SECCOMP failed")
'''
    runner = r'''
import os
import runpy
import sys
script = sys.argv[1]
sys.argv = [script] + sys.argv[2:]
sys.path.insert(0, os.path.dirname(script))
runpy.run_path(script, run_name="__main__")
'''
    with open(os.path.join(guard_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
        f.write(sitecustomize)
    with open(os.path.join(guard_dir, "runner.py"), "w", encoding="utf-8") as f:
        f.write(runner)
    os.chmod(os.path.join(guard_dir, "sitecustomize.py"), 0o644)
    os.chmod(os.path.join(guard_dir, "runner.py"), 0o644)


def test_fuzz_equivalence():
    oracle_path = "/app/time_oracle"
    agent_script = "/home/user/processor.py"

    assert os.path.isfile(oracle_path), f"Oracle binary missing at {oracle_path}"
    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"

    # Hide the oracle from the submitted program while retaining a root-only verifier copy.
    secret_dir = tempfile.mkdtemp(prefix="verifier-oracle-", dir="/tmp")
    os.chmod(secret_dir, 0o700)
    verifier_oracle = os.path.join(secret_dir, "time_oracle")
    shutil.copy2(oracle_path, verifier_oracle)
    os.chmod(verifier_oracle, 0o700)
    os.unlink(oracle_path)

    guard_dir = "/tmp/verifier-python-guard"
    _install_exec_guard(guard_dir)

    account = pwd.getpwnam("user")
    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    env = os.environ.copy()
    env["HOME"] = account.pw_dir
    env["PYTHONPATH"] = guard_dir
    env["PYTHONNOUSERSITE"] = "1"

    random.seed(42)
    num_tests = 1000

    for _ in range(num_tests):
        timestamp = str(random.randint(0, 2000000000))

        oracle_res = subprocess.run([verifier_oracle, timestamp], capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on input {timestamp}"
        oracle_out = oracle_res.stdout.strip()

        agent_res = subprocess.run(
            ["/usr/bin/python3", "-s", os.path.join(guard_dir, "runner.py"), agent_script, timestamp],
            capture_output=True,
            text=True,
            env=env,
            cwd="/tmp",
            preexec_fn=demote,
        )
        assert agent_res.returncode == 0, f"Agent script failed on input {timestamp}. Stderr: {agent_res.stderr}"
        agent_out = agent_res.stdout.strip()

        # Preserve the original equivalence assertion.
        assert agent_out == oracle_out, (
            f"Output mismatch on timestamp {timestamp}.\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output:  {agent_out}"
        )
        assert agent_res.stdout == oracle_res.stdout, "Output must be bit-exact, including its newline"
        assert agent_res.stderr == "", f"Processor printed unexpected stderr: {agent_res.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
