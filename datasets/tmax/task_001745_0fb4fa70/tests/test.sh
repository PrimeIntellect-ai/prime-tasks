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
import os
import random
import shutil
import string
import subprocess
import time
from pathlib import Path

import pytest
import requests

URL = "http://127.0.0.1:8080/api/v1/projects"
AUTH_HEADER = {"Authorization": "Bearer GraphMaster2024"}
EMPLOYEES = Path("/home/user/employees.csv")
PROJECTS = Path("/home/user/projects.csv")
SERVER_COPY = Path("/tmp/submission-go-server")


def wait_for_server(url, timeout=5):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            requests.get(url, timeout=1)
            return True
        except requests.exceptions.ConnectionError:
            time.sleep(0.25)
    return False


def listener_pids():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[1].endswith(":1F90") and fields[3] == "0A":
                inodes.add(fields[9])

    found = set()
    for proc_dir in Path("/proc").iterdir():
        if not proc_dir.name.isdigit():
            continue
        fd_dir = proc_dir / "fd"
        try:
            for fd in fd_dir.iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    found.add(int(proc_dir.name))
        except OSError:
            continue
    return found


def read_process_environment(pid):
    env = os.environ.copy()
    try:
        raw = Path(f"/proc/{pid}/environ").read_bytes()
        for entry in raw.split(b"\0"):
            if b"=" in entry:
                key, value = entry.split(b"=", 1)
                env[key.decode(errors="ignore")] = value.decode(errors="ignore")
    except OSError:
        pass
    return env


def stop_all_listeners():
    deadline = time.time() + 3
    while time.time() < deadline:
        pids = listener_pids()
        if not pids:
            return
        for pid in pids:
            try:
                os.kill(pid, 15)
            except ProcessLookupError:
                pass
        time.sleep(0.15)
    for pid in listener_pids():
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass
    time.sleep(0.2)


def start_server(cwd, env):
    proc = subprocess.Popen(
        [str(SERVER_COPY)], cwd=cwd, env=env,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    assert wait_for_server(URL, 5), "Restarted Go artifact did not listen on 127.0.0.1:8080"
    return proc


def write_dataset(employee_rows, project_rows):
    employee_text = "emp_id,name,manager_id,department\n" + "\n".join(
        ",".join(map(str, row)) for row in employee_rows
    ) + "\n"
    project_text = "emp_id,project_name,status\n" + "\n".join(
        ",".join(map(str, row)) for row in project_rows
    ) + "\n"
    EMPLOYEES.write_text(employee_text)
    PROJECTS.write_text(project_text)


def expected_count(employee_rows, project_rows):
    alice_ids = {str(row[0]) for row in employee_rows if row[1] == "Alice"}
    assert len(alice_ids) == 1
    included = set(alice_ids)
    changed = True
    while changed:
        changed = False
        for emp_id, _name, manager_id, _department in employee_rows:
            if str(manager_id) in included and str(emp_id) not in included:
                included.add(str(emp_id))
                changed = True
    return len({str(project) for emp_id, project, _status in project_rows if str(emp_id) in included})


def make_dataset(rng, forbidden_counts):
    while True:
        descendant_count = rng.randint(3, 8)
        employees = [
            (101, "CEO", "NULL", "Exec"),
            (207, "Alice", 101, "Engineering"),
        ]
        descendant_ids = []
        possible_managers = [207]
        for i in range(descendant_count):
            emp_id = 300 + i * 13
            manager = rng.choice(possible_managers)
            employees.append((emp_id, f"Worker{i}", manager, "Engineering"))
            descendant_ids.append(emp_id)
            possible_managers.append(emp_id)
        employees.extend([
            (801, "OutsideManager", 101, "Sales"),
            (802, "OutsideChild", 801, "Sales"),
        ])
        rng.shuffle(employees)

        token = "".join(rng.choice(string.ascii_letters) for _ in range(10))
        relevant = [207] + descendant_ids
        project_names = [f"P_{token}_{i}" for i in range(rng.randint(3, 10))]
        projects = []
        for emp_id in relevant:
            for _ in range(rng.randint(1, 3)):
                projects.append((emp_id, rng.choice(project_names), rng.choice(["Active", "Completed", "Paused"])))
        # Ensure completed projects count and duplicates must be handled, while outsiders do not count.
        projects.append((relevant[-1], f"Completed_{token}", "Completed"))
        projects.append((207, project_names[0], "Active"))
        projects.append((relevant[-1], project_names[0], "Completed"))
        projects.append((801, f"Outside_{token}", "Active"))
        projects.append((802, f"OutsideChild_{token}", "Active"))
        rng.shuffle(projects)
        answer = expected_count(employees, projects)
        if answer not in forbidden_counts:
            return employees, projects, answer


def test_server_running_and_unauthorized_without_token():
    wait_for_server(URL)
    try:
        response = requests.get(URL, timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the Go server on 127.0.0.1:8080. Is it running?")
    assert response.status_code == 401, f"Expected 401 Unauthorized without token, got {response.status_code}"


def test_unauthorized_with_invalid_token():
    try:
        response = requests.get(URL, headers={"Authorization": "Bearer InvalidToken123"}, timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the Go server on 127.0.0.1:8080. Is it running?")
    assert response.status_code == 401, f"Expected 401 Unauthorized with invalid token, got {response.status_code}"


def test_authorized_request_returns_correct_result():
    try:
        response = requests.get(URL, headers=AUTH_HEADER, timeout=2)
    except requests.exceptions.ConnectionError:
        pytest.fail("Failed to connect to the Go server on 127.0.0.1:8080. Is it running?")
    assert response.status_code == 200, f"Expected 200 OK with valid token, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")
    assert "result_count" in data, f"Response JSON missing 'result_count' key. Got: {data}"
    assert data["result_count"] == 5, f"Expected result_count to be 5, got {data['result_count']}"


def test_go_artifact_reads_csv_and_performs_recursive_distinct_aggregation():
    pids = listener_pids()
    assert pids, "Could not identify the process listening on port 8080"
    pid = next(iter(pids))
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = read_process_environment(pid)
    shutil.copyfile(f"/proc/{pid}/exe", SERVER_COPY)
    SERVER_COPY.chmod(0o755)

    go_info = subprocess.run(
        ["go", "version", "-m", str(SERVER_COPY)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=5,
    )
    assert go_info.returncode == 0 and "go1" in go_info.stdout, (
        "The process serving port 8080 is not a Go executable"
    )

    original_employees = EMPLOYEES.read_bytes()
    original_projects = PROJECTS.read_bytes()
    proc = None
    rng = random.SystemRandom()
    used_answers = {5}
    try:
        stop_all_listeners()
        for _ in range(4):
            employee_rows, project_rows, answer = make_dataset(rng, used_answers)
            used_answers.add(answer)
            write_dataset(employee_rows, project_rows)
            proc = start_server(cwd, env)

            response = requests.get(URL, headers=AUTH_HEADER, timeout=2)
            assert response.status_code == 200
            try:
                data = response.json()
            except ValueError:
                pytest.fail(f"Response is not valid JSON for generated CSV data: {response.text}")
            assert data == {"result_count": answer}, (
                f"For generated CSV graph, expected exactly {{'result_count': {answer}}}, got {data}"
            )

            no_token = requests.get(URL, timeout=2)
            bad_token = requests.get(URL, headers={"Authorization": "Bearer wrong"}, timeout=2)
            assert no_token.status_code == 401
            assert bad_token.status_code == 401
            stop_all_listeners()
            proc = None
    finally:
        stop_all_listeners()
        EMPLOYEES.write_bytes(original_employees)
        PROJECTS.write_bytes(original_projects)
        if SERVER_COPY.exists():
            try:
                start_server(cwd, env)
            except Exception:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
