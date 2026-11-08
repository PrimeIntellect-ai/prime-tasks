#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import asyncio
import json
import math
import os
import secrets
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time

import pytest

REPO_DIR = "/home/user/numsock_repo"
DB_PATH = os.path.join(REPO_DIR, "data.db")
FINAL_RESULT_PATH = "/home/user/final_result.json"
PYPROJECT_PATH = os.path.join(REPO_DIR, "pyproject.toml")
SERVER_PATH = os.path.join(REPO_DIR, "numsock", "server.py")


def test_pyproject_toml_fixed():
    """Verify pyproject.toml is valid, declares websockets, and installs editably."""
    assert os.path.isfile(PYPROJECT_PATH), "pyproject.toml is missing."
    with open(PYPROJECT_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original assertions.
    assert 'name = "numsock"' in content or "name = 'numsock'" in content, \
        "The 'name' field in pyproject.toml is still broken."
    assert "websockets" in content, \
        "The 'websockets' dependency is missing from pyproject.toml."

    try:
        import tomllib
        parsed = tomllib.loads(content)
    except Exception as exc:
        pytest.fail(f"pyproject.toml is not valid TOML: {exc}")

    project = parsed.get("project")
    assert isinstance(project, dict), "pyproject.toml has no valid [project] table."
    assert project.get("name") == "numsock", "The project name must be numsock."
    dependencies = project.get("dependencies")
    assert isinstance(dependencies, list), "Project dependencies must be a TOML array."

    try:
        from packaging.requirements import Requirement
        names = {Requirement(item).name.lower() for item in dependencies if isinstance(item, str)}
    except Exception as exc:
        pytest.fail(f"Project dependencies are malformed: {exc}")
    assert "websockets" in names, "The websockets package is not a declared dependency."

    result = subprocess.run(
        [sys.executable, "-m", "pip", "install", "-e", ".", "--no-deps"],
        cwd=REPO_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, f"Editable installation failed:\n{result.stdout}"

    imported = subprocess.run(
        [sys.executable, "-c", "import os, numsock; print(os.path.realpath(numsock.__file__))"],
        cwd="/tmp",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=15,
    )
    assert imported.returncode == 0, f"Installed numsock cannot be imported:\n{imported.stdout}"
    assert os.path.realpath(REPO_DIR) in imported.stdout, \
        "Editable installation does not import numsock from the submitted repository."


def test_database_schema_and_contents():
    """Verify that the SQLite database has the correct schema and data."""
    assert os.path.isfile(DB_PATH), "data.db is missing. The server might not have run or initialized the DB."

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    c.execute("PRAGMA table_info(records)")
    columns = {row["name"]: row["type"].upper() for row in c.fetchall()}

    assert "ema" in columns, "The 'ema' column is missing from the 'records' table."
    assert "FLOATX" not in columns.get("ema", ""), "The 'ema' column has the invalid type 'FLOATX'."

    c.execute("SELECT id, value, ema FROM records ORDER BY id ASC")
    rows = c.fetchall()

    assert len(rows) >= 3, "The database does not contain the expected number of records."

    expected_values = [10.0, 20.0, 15.0]
    expected_emas = []
    alpha = 0.5
    last_ema = None
    for v in expected_values:
        if last_ema is None:
            last_ema = v
        else:
            last_ema = (v * alpha) + (last_ema * (1 - alpha))
        expected_emas.append(last_ema)

    for i in range(3):
        assert float(rows[i]["value"]) == expected_values[i], f"Record {i+1} value mismatch."
        assert float(rows[i]["ema"]) == expected_emas[i], f"Record {i+1} ema mismatch."

    conn.close()


def test_final_result_json():
    """Verify that final_result.json matches the expected output."""
    assert os.path.isfile(FINAL_RESULT_PATH), "final_result.json is missing."

    with open(FINAL_RESULT_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("final_result.json does not contain valid JSON.")

    assert isinstance(data, list), "final_result.json must contain a JSON array."
    assert len(data) >= 3, "final_result.json does not contain enough records."

    expected_values = [10.0, 20.0, 15.0]
    expected_emas = [10.0, 15.0, 15.0]

    for i in range(3):
        row = data[i]
        assert "id" in row and "value" in row and "ema" in row, f"Row {i+1} is missing required keys."
        assert float(row["value"]) == expected_values[i], f"JSON Row {i+1} value mismatch."
        assert float(row["ema"]) == expected_emas[i], f"JSON Row {i+1} ema mismatch."


def _kill_port_8765_listeners():
    """Stop a server left running by the agent so the submitted server can be tested."""
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        if int(fields[1].rsplit(":", 1)[1], 16) == 8765:
                            inodes.add(fields[9])
        except OSError:
            pass

    victims = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(name))
                    break
        except OSError:
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def test_server_with_unpredictable_websocket_inputs():
    """Run the submitted server and verify JSON replies and persisted EMA values."""
    assert os.path.isfile(SERVER_PATH), "numsock/server.py is missing."

    with open(SERVER_PATH, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=SERVER_PATH)
    insert_aliases = {"insert_record"}
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom):
            for item in node.names:
                if item.name == "insert_record":
                    insert_aliases.add(item.asname or item.name)
    calls_insert = any(
        isinstance(node, ast.Call) and (
            (isinstance(node.func, ast.Name) and node.func.id in insert_aliases) or
            (isinstance(node.func, ast.Attribute) and node.func.attr == "insert_record")
        )
        for node in ast.walk(tree)
    )
    assert calls_insert, "server.py does not call insert_record to persist received values."

    # Values are generated only at verification time, so fixed-row fabrication cannot pass.
    rng = secrets.SystemRandom()
    values = []
    while len(values) < 5:
        value = rng.randint(-20000, 20000) / 8.0
        if value not in values and value not in (10.0, 20.0, 15.0):
            values.append(value)

    expected = []
    current = None
    for value in values:
        current = value if current is None else value * 0.5 + current * 0.5
        expected.append(current)

    _kill_port_8765_listeners()

    backup_dir = tempfile.mkdtemp(prefix="numsock-verifier-")
    backup_path = os.path.join(backup_dir, "original.db")
    had_original = os.path.exists(DB_PATH)
    if had_original:
        shutil.copy2(DB_PATH, backup_path)
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    proc = subprocess.Popen(
        [sys.executable, "-m", "numsock.server"],
        cwd=REPO_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    async def exercise():
        import websockets

        ws = None
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                output = proc.stdout.read() if proc.stdout else ""
                raise AssertionError(f"Server exited before accepting connections:\n{output}")
            try:
                ws = await websockets.connect("ws://localhost:8765")
                break
            except Exception:
                await asyncio.sleep(0.1)
        assert ws is not None, "Submitted server did not listen on localhost:8765."

        try:
            for value, wanted in zip(values, expected):
                await ws.send(json.dumps({"value": value}))
                raw = await asyncio.wait_for(ws.recv(), timeout=3)
                try:
                    response = json.loads(raw)
                except (TypeError, json.JSONDecodeError) as exc:
                    raise AssertionError(f"WebSocket response is not valid JSON: {raw!r}") from exc
                assert isinstance(response, dict), "WebSocket response must be a JSON object."
                assert set(response) == {"ema"}, "WebSocket response must have exactly the 'ema' key."
                assert isinstance(response["ema"], (int, float)) and not isinstance(response["ema"], bool), \
                    "The response ema must be numeric."
                assert math.isclose(float(response["ema"]), wanted, rel_tol=1e-12, abs_tol=1e-12), \
                    f"Incorrect EMA for input {value}."
        finally:
            await ws.close()

    try:
        asyncio.run(exercise())

        assert os.path.isfile(DB_PATH), "The running server did not create data.db."
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        try:
            columns = {row["name"]: row["type"].upper() for row in conn.execute("PRAGMA table_info(records)")}
            assert "ema" in columns, "The server-created records table lacks the ema column."
            assert "FLOATX" not in columns.get("ema", ""), "The server created ema with invalid FLOATX type."
            rows = conn.execute("SELECT id, value, ema FROM records ORDER BY id").fetchall()
            assert len(rows) == len(values), "The server did not insert exactly one row per WebSocket message."
            for i, (row, value, wanted) in enumerate(zip(rows, values, expected), 1):
                assert math.isclose(float(row["value"]), value, rel_tol=0, abs_tol=1e-12), \
                    f"Persisted value mismatch in dynamic row {i}."
                assert math.isclose(float(row["ema"]), wanted, rel_tol=1e-12, abs_tol=1e-12), \
                    f"Persisted EMA mismatch in dynamic row {i}."
        finally:
            conn.close()
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)
        if had_original:
            shutil.copy2(backup_path, DB_PATH)
        elif os.path.exists(DB_PATH):
            os.remove(DB_PATH)
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
