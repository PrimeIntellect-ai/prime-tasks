#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import shutil
import signal
import socket
import sqlite3
import subprocess
import time
from pathlib import Path

import pytest
import requests

URL = "http://127.0.0.1:8080/api/result"
EXPECTED_KEYS = {"transcript", "researcher", "location", "projects", "total_budget"}


def get_result(timeout=5):
    response = requests.get(URL, timeout=timeout)
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")


def listener_pid():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].split(":")[-1].upper() == "1F90" and fields[3] == "0A":
                inodes.add(fields[9])

    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        fd_dir = proc / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(proc.name)
        except (OSError, PermissionError):
            continue
    raise AssertionError("Could not identify the process listening on port 8080")


def process_info(pid):
    proc = Path(f"/proc/{pid}")
    raw_cmd = (proc / "cmdline").read_bytes().split(b"\0")
    cmd = [part.decode(errors="surrogateescape") for part in raw_cmd if part]
    assert cmd, "The listening process has an empty command line"
    cwd = os.readlink(proc / "cwd")
    env = os.environ.copy()
    try:
        for item in (proc / "environ").read_bytes().split(b"\0"):
            if b"=" in item:
                key, value = item.split(b"=", 1)
                env[key.decode(errors="surrogateescape")] = value.decode(errors="surrogateescape")
    except OSError:
        pass
    return cmd, cwd, env


def locate_python_script(cmd, cwd):
    for arg in cmd[1:]:
        if arg.endswith(".py"):
            path = Path(arg)
            if not path.is_absolute():
                path = Path(cwd) / path
            path = path.resolve()
            assert path.is_file(), f"Python server script does not exist: {path}"
            return path
    raise AssertionError("The listener was not launched from the required Python script")


def inspect_implementation(script):
    roots = [script]
    for path in script.parent.rglob("*.py"):
        if path != script and "__pycache__" not in path.parts:
            roots.append(path)

    texts = []
    parameterized_execute = False
    total_size = 0
    for path in roots:
        try:
            if path.stat().st_size > 1_000_000:
                continue
            text = path.read_text(errors="replace")
        except OSError:
            continue
        total_size += len(text)
        if total_size > 5_000_000:
            break
        texts.append(text)
        try:
            tree = ast.parse(text, filename=str(path))
        except SyntaxError:
            continue
        for node in ast.walk(tree):
            if (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                    and node.func.attr in {"execute", "executemany"}
                    and len(node.args) >= 2):
                parameterized_execute = True

    source = "\n".join(texts)
    lowered = source.lower()
    assert "dictation.wav" in lowered, "Server implementation does not read the required audio file"
    assert "knowledge.db" in lowered, "Server implementation does not connect to the required database"
    assert "sqlite3" in lowered, "Server implementation does not use SQLite"
    assert "select" in lowered and "join" in lowered, "No joined SELECT query was found"
    assert "?" in source and parameterized_execute, "SQLite queries are not executed with bound parameters"
    assert "sum(" in lowered, "No budget aggregation was found in the implementation"


def stop_server(pid):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    for _ in range(30):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.1)
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    time.sleep(0.3)


def wait_for_result(timeout=120):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            return get_result(timeout=3)
        except Exception as exc:
            last_error = exc
            time.sleep(0.5)
    raise AssertionError(f"Restarted server did not become ready: {last_error}")


def install_alternate_fixture():
    subprocess.run(
        ["espeak", "-w", "/app/dictation.wav", "Subject: Bob Smith. Location: Paris."],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    with sqlite3.connect("/app/knowledge.db") as db:
        db.executescript("""
        DELETE FROM researcher_project;
        DELETE FROM facility_project;
        DELETE FROM researchers;
        DELETE FROM facilities;
        DELETE FROM projects;

        INSERT INTO researchers VALUES (10, 'Bob Smith', 'Artificial Intelligence');
        INSERT INTO researchers VALUES (11, 'Unrelated Person', 'Biology');
        INSERT INTO facilities VALUES (20, 'Paris', 'France');
        INSERT INTO facilities VALUES (21, 'Rome', 'Italy');

        INSERT INTO projects VALUES (30, 'Atlas Study', 111111.25);
        INSERT INTO projects VALUES (31, 'Zenith Lab', 222222.75);
        INSERT INTO projects VALUES (32, 'Researcher Only', 999999.0);
        INSERT INTO projects VALUES (33, 'Facility Only', 888888.0);

        INSERT INTO researcher_project VALUES (10, 30);
        INSERT INTO researcher_project VALUES (10, 31);
        INSERT INTO researcher_project VALUES (10, 32);
        INSERT INTO researcher_project VALUES (11, 33);

        INSERT INTO facility_project VALUES (20, 30);
        INSERT INTO facility_project VALUES (20, 31);
        INSERT INTO facility_project VALUES (21, 32);
        INSERT INTO facility_project VALUES (20, 33);
        """)


def test_complete_pipeline():
    # Preserve all assertions made by the original verifier, with exact transcription added.
    original = get_result()
    assert "transcript" in original, "Missing 'transcript' in JSON response"
    assert isinstance(original["transcript"], str)
    transcript_lower = original["transcript"].lower()
    assert "alice" in transcript_lower and "johnson" in transcript_lower
    assert "berlin" in transcript_lower
    assert original["transcript"] == "Subject: Alice Johnson. Location: Berlin."
    assert original.get("researcher") == "Alice Johnson"
    assert original.get("location") == "Berlin"
    assert original.get("projects") == ["Project Alpha", "Project Beta"]
    assert original.get("total_budget") == 1250000.0

    pid = listener_pid()
    cmd, cwd, env = process_info(pid)
    script = locate_python_script(cmd, cwd)
    inspect_implementation(script)

    wav_backup = "/tmp/verifier_dictation.wav"
    db_backup = "/tmp/verifier_knowledge.db"
    shutil.copy2("/app/dictation.wav", wav_backup)
    shutil.copy2("/app/knowledge.db", db_backup)
    child = None
    try:
        stop_server(pid)
        install_alternate_fixture()
        child = subprocess.Popen(
            cmd,
            cwd=cwd,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        changed = wait_for_result()
        assert set(changed) == EXPECTED_KEYS, f"Unexpected JSON structure: {changed}"
        assert changed["transcript"] == "Subject: Bob Smith. Location: Paris."
        assert changed["researcher"] == "Bob Smith"
        assert changed["location"] == "Paris"
        assert changed["projects"] == ["Atlas Study", "Zenith Lab"]
        assert changed["total_budget"] == pytest.approx(334334.0)
    finally:
        try:
            active = listener_pid()
            stop_server(active)
        except Exception:
            if child is not None and child.poll() is None:
                child.kill()
        shutil.copy2(wav_backup, "/app/dictation.wav")
        shutil.copy2(db_backup, "/app/knowledge.db")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
