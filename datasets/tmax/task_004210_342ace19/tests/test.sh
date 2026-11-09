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
import os
import random
import secrets
import signal
import sqlite3
import string
import subprocess
import sys
import time
from pathlib import Path

import pytest
import requests
from PIL import Image, ImageDraw, ImageFont

URL = "http://127.0.0.1:8080/api/employees"


def assert_employee_response(data, expected_data):
    assert isinstance(data, list), f"Expected response to be a JSON array, got {type(data)}"
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} employees, got {len(data)}"

    for i, expected_emp in enumerate(expected_data):
        actual_emp = data[i]
        assert actual_emp.get("employee_id") == expected_emp["employee_id"], f"Mismatch at index {i}: expected employee_id {expected_emp['employee_id']}, got {actual_emp.get('employee_id')}"
        assert actual_emp.get("name") == expected_emp["name"], f"Mismatch at index {i}: expected name {expected_emp['name']}, got {actual_emp.get('name')}"
        assert actual_emp.get("department_name") == expected_emp["department_name"], f"Mismatch at index {i}: expected department_name {expected_emp['department_name']}, got {actual_emp.get('department_name')}"
        assert actual_emp.get("salary_rank") == expected_emp["salary_rank"], f"Mismatch at index {i}: expected salary_rank {expected_emp['salary_rank']}, got {actual_emp.get('salary_rank')}"

        # Preserve the original verifier's login-count assertion.
        actual_login_count = actual_emp.get("login_count", 0)
        assert actual_login_count == expected_emp["login_count"], f"Mismatch at index {i}: expected login_count {expected_emp['login_count']}, got {actual_login_count}"


def get_json(url=URL, timeout=5):
    try:
        response = requests.get(url, timeout=timeout)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {url}. Error: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")


def listening_pids(port):
    inodes = set()
    target = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == target and fields[3] == "0A":
                inodes.add(fields[9])

    owners = set()
    if not inodes:
        return owners
    for proc_dir in Path("/proc").iterdir():
        if not proc_dir.name.isdigit():
            continue
        try:
            for fd in (proc_dir / "fd").iterdir():
                try:
                    link = os.readlink(fd)
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    owners.add(int(proc_dir.name))
        except (OSError, PermissionError):
            continue
    return owners


def stop_server():
    for pid in listening_pids(8080):
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    deadline = time.time() + 3
    while listening_pids(8080) and time.time() < deadline:
        time.sleep(0.05)
    for pid in listening_pids(8080):
        if pid != os.getpid():
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def test_01_original_api_employees_endpoint():
    data = get_json()
    expected_data = [
        {"employee_id": 1, "name": "Alice", "department_name": "Engineering", "salary_rank": 2, "login_count": 2},
        {"employee_id": 2, "name": "Bob", "department_name": "Engineering", "salary_rank": 1, "login_count": 0},
        {"employee_id": 3, "name": "Charlie", "department_name": "Sales", "salary_rank": 1, "login_count": 1},
        {"employee_id": 4, "name": "Diana", "department_name": "Operations", "salary_rank": 1, "login_count": 0},
    ]
    assert_employee_response(data, expected_data)


def test_02_reexecute_etl_against_derived_inputs():
    etl = Path("/app/etl.py")
    assert etl.is_file(), "/app/etl.py does not exist or is not a regular file"

    stop_server()

    rng = random.SystemRandom()
    employee_ids = sorted(rng.sample(range(20, 900), 6))
    department_ids = ["D1", "D2", "D3"]
    assignments = ["D1", "D1", "D2", "D2", "D3", "D3"]
    rng.shuffle(assignments)
    salaries = rng.sample(range(60000, 180000), 6)

    def word(prefix):
        return prefix + "".join(secrets.choice(string.ascii_uppercase) for _ in range(7))

    employee_names = [word("Emp") for _ in employee_ids]
    mappings = {department_id: word("Dept") for department_id in department_ids}
    login_counts = [3, 0, 2, 1, 4, 0]
    rng.shuffle(login_counts)

    db_tmp = Path("/app/data.dynamic.db")
    if db_tmp.exists():
        db_tmp.unlink()
    conn = sqlite3.connect(db_tmp)
    cur = conn.cursor()
    cur.execute("CREATE TABLE employees (id INTEGER, name TEXT, salary INTEGER)")
    cur.execute("CREATE TABLE departments (id TEXT)")
    cur.execute("CREATE TABLE employee_departments (employee_id INTEGER, department_id TEXT)")
    cur.executemany("INSERT INTO employees VALUES (?, ?, ?)", list(zip(employee_ids, employee_names, salaries)))
    cur.executemany("INSERT INTO departments VALUES (?)", [(d,) for d in department_ids])
    cur.executemany("INSERT INTO employee_departments VALUES (?, ?)", list(zip(employee_ids, assignments)))
    conn.commit()
    conn.close()
    os.replace(db_tmp, "/app/data.db")

    with open("/app/events.json", "w", encoding="utf-8") as events:
        for employee_id, count in zip(employee_ids, login_counts):
            for _ in range(count):
                events.write(json.dumps({"employee_id": employee_id, "event_type": "login"}) + "\n")
            events.write(json.dumps({"employee_id": employee_id, "event_type": "logout"}) + "\n")
        events.write(json.dumps({"employee_id": 999999, "event_type": "login"}) + "\n")

    mapping_text = "MAPPING: " + json.dumps(mappings)
    image = Image.new("RGB", (1500, 130), "white")
    draw = ImageDraw.Draw(image)
    font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    font = ImageFont.truetype(font_path, 32) if os.path.exists(font_path) else ImageFont.load_default()
    draw.text((20, 35), mapping_text, fill="black", font=font)
    image.save("/app/schema_clue.png")

    expected = []
    for employee_id, name, salary, department_id, count in zip(employee_ids, employee_names, salaries, assignments, login_counts):
        department_salaries = sorted(
            (s for s, d in zip(salaries, assignments) if d == department_id),
            reverse=True,
        )
        expected.append({
            "employee_id": employee_id,
            "name": name,
            "department_name": mappings[department_id],
            "salary_rank": department_salaries.index(salary) + 1,
            "login_count": count,
        })
    expected.sort(key=lambda row: row["employee_id"])

    instrument_dir = Path("/tmp/etl_instrument")
    instrument_dir.mkdir(exist_ok=True)
    trace_file = Path("/tmp/etl_sql_trace.log")
    trace_file.unlink(missing_ok=True)
    (instrument_dir / "sitecustomize.py").write_text(
        "import sqlite3\n"
        "_real_connect = sqlite3.connect\n"
        "def _connect(*args, **kwargs):\n"
        "    connection = _real_connect(*args, **kwargs)\n"
        "    def _trace(statement):\n"
        "        with open('/tmp/etl_sql_trace.log', 'a', encoding='utf-8') as out:\n"
        "            out.write(statement.replace('\\x00', ' ') + '\\x00')\n"
        "    connection.set_trace_callback(_trace)\n"
        "    return connection\n"
        "sqlite3.connect = _connect\n",
        encoding="utf-8",
    )

    env = os.environ.copy()
    env["PYTHONPATH"] = str(instrument_dir) + os.pathsep + env.get("PYTHONPATH", "")
    proc = subprocess.Popen(
        [sys.executable, str(etl)],
        cwd="/app",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )

    try:
        response_data = None
        last_error = None
        deadline = time.time() + 15
        while time.time() < deadline:
            try:
                response = requests.get(URL, timeout=1)
                if response.status_code == 200:
                    response_data = response.json()
                    break
                last_error = f"HTTP {response.status_code}: {response.text}"
            except Exception as exc:
                last_error = repr(exc)
            time.sleep(0.15)

        if response_data is None:
            output = ""
            if proc.poll() is not None and proc.stdout is not None:
                output = proc.stdout.read()
            pytest.fail(f"Re-executed /app/etl.py did not serve the endpoint: {last_error}. Output: {output}")

        assert_employee_response(response_data, expected)
        for item in response_data:
            assert set(item) >= {"employee_id", "name", "department_name", "salary_rank", "login_count"}
            assert type(item["salary_rank"]) is int
            assert type(item["login_count"]) is int

        statements = trace_file.read_text(encoding="utf-8").split("\x00") if trace_file.exists() else []
        qualifying = []
        for statement in statements:
            sql = " ".join(statement.lower().split())
            if (
                "employees" in sql
                and "departments" in sql
                and "employee_departments" in sql
                and " over " in f" {sql} "
                and any(fn + "(" in sql.replace(" ", "") for fn in ("rank", "dense_rank", "row_number"))
                and sql.count(" join ") >= 2
            ):
                qualifying.append(statement)
        assert qualifying, "The executed SQL did not join all three tables and calculate salary rank with a SQL window function"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
        stop_server()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
