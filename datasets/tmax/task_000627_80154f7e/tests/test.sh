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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import shlex
import sqlite3
import uuid

import pytest
import requests

BINARY_PATH = "/home/user/engine"
BASE_URL = "http://127.0.0.1:8080/user_stats"


def test_engine_binary_exists():
    assert os.path.isfile(BINARY_PATH), f"C++ engine binary not found at {BINARY_PATH}"
    assert os.access(BINARY_PATH, os.X_OK), f"File at {BINARY_PATH} is not executable"
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File at {BINARY_PATH} is not a compiled executable"


def check_response(user_id, expected_email, expected_total):
    try:
        response = requests.get(BASE_URL, params={"user_id": str(user_id)}, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP service at {BASE_URL}: {e}")

    assert response.status_code == 200, f"Expected HTTP status code 200, got {response.status_code}"

    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, f"Expected Content-Type 'application/json', got '{content_type}'"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON: {response.text}")

    assert "email" in data, "Response JSON missing 'email' field"
    assert "total_spent" in data, "Response JSON missing 'total_spent' field"
    assert data["email"] == expected_email, f"Expected email '{expected_email}', got '{data['email']}'"
    assert math.isclose(float(data["total_spent"]), float(expected_total), rel_tol=1e-9, abs_tol=1e-7), \
        f"Expected total_spent {expected_total}, got {data['total_spent']}"


def test_http_service_response():
    check_response(101, "alice@example.com", 26.0)


def engine_is_running():
    target = os.stat(BINARY_PATH)
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            proc_exe = os.stat(f"/proc/{pid}/exe")
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if proc_exe.st_dev == target.st_dev and proc_exe.st_ino == target.st_ino:
            return True
    return False


def insert_random_cases():
    conn = sqlite3.connect("/home/user/data.db", timeout=10)
    try:
        ids = []
        while len(ids) < 3:
            candidate = 1_000_000 + secrets.randbelow(1_000_000_000)
            if candidate in ids:
                continue
            if conn.execute("SELECT 1 FROM users WHERE id = ?", (candidate,)).fetchone() is None:
                ids.append(candidate)

        next_order = conn.execute("SELECT COALESCE(MAX(order_id), 0) + 1 FROM orders").fetchone()[0]
        for index, user_id in enumerate(ids):
            email = f"verify-{uuid.uuid4().hex}@example.test"
            conn.execute(
                "INSERT INTO users(id, profile) VALUES (?, ?)",
                (user_id, json.dumps({"email": email})),
            )

            cents = [secrets.randbelow(9000) + 101 for _ in range(4)]
            quantities = [secrets.randbelow(5) + 1 for _ in range(4)]
            first_items = [
                {"price": cents[0] / 100.0, "qty": quantities[0]},
                {"price": cents[1] / 100.0, "qty": quantities[1]},
            ]
            second_items = [
                {"price": cents[2] / 100.0, "qty": quantities[2]},
                {"price": cents[3] / 100.0, "qty": quantities[3]},
            ]
            conn.execute(
                "INSERT INTO orders(order_id, user_id, items) VALUES (?, ?, ?)",
                (next_order + index * 2, user_id, json.dumps(first_items)),
            )
            conn.execute(
                "INSERT INTO orders(order_id, user_id, items) VALUES (?, ?, ?)",
                (next_order + index * 2 + 1, user_id, json.dumps(second_items)),
            )
        conn.commit()

        expected = []
        for user_id in ids:
            row = conn.execute(
                """
                SELECT json_extract(u.profile, '$.email'),
                       SUM(json_extract(item.value, '$.price') *
                           json_extract(item.value, '$.qty'))
                FROM users AS u
                JOIN orders AS o ON o.user_id = u.id
                JOIN json_each(o.items) AS item
                WHERE u.id = ?
                GROUP BY u.id
                """,
                (user_id,),
            ).fetchone()
            assert row is not None
            expected.append((user_id, row[0], row[1]))
        return expected
    finally:
        conn.close()


def test_randomized_database_queries_and_engine_execution():
    expected_cases = insert_random_cases()
    already_running = engine_is_running()

    real_path = f"/home/user/.engine.verifier-real-{uuid.uuid4().hex}"
    marker_path = f"/tmp/engine-invoked-{uuid.uuid4().hex}"
    instrumented = False

    if not already_running:
        os.rename(BINARY_PATH, real_path)
        with open(BINARY_PATH, "w", encoding="utf-8") as wrapper:
            wrapper.write("#!/bin/sh\n")
            wrapper.write(f": > {shlex.quote(marker_path)}\n")
            wrapper.write(f"exec {shlex.quote(real_path)} \"$@\"\n")
        os.chmod(BINARY_PATH, 0o755)
        instrumented = True

    try:
        for user_id, email, total in expected_cases:
            check_response(user_id, email, total)
        assert already_running or os.path.exists(marker_path), \
            "The HTTP service did not execute /home/user/engine"
    finally:
        if instrumented:
            try:
                os.unlink(BINARY_PATH)
            except FileNotFoundError:
                pass
            os.rename(real_path, BINARY_PATH)
        try:
            os.unlink(marker_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
