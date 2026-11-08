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
import re
import signal
import subprocess
import time
import uuid
from pathlib import Path

import pytest
import requests

URL = "http://127.0.0.1:8080/query"


def test_database_directory_exists():
    """Verify that the Kùzu database directory was created."""
    db_path = "/home/user/graph_db"
    assert os.path.isdir(db_path), f"Database directory {db_path} does not exist."


def test_api_log_exists():
    """Verify that the API log file was created."""
    log_path = "/home/user/api.log"
    assert os.path.isfile(log_path), f"API log file {log_path} does not exist."


def query_api(employee_id, timeout=5):
    try:
        response = requests.post(URL, json={"employee_id": employee_id}, timeout=timeout)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API at {URL}: {e}")
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )
    data = response.json()
    assert "projects" in data, f"Response JSON missing 'projects' key: {data}"
    assert isinstance(data["projects"], list), f"'projects' must be a list: {data}"
    return data["projects"]


def test_api_query_e101():
    """Test the POST /query endpoint for employee E101."""
    expected_projects = {"Project Titan", "Project Apollo"}
    actual_projects = set(query_api("E101"))
    assert actual_projects == expected_projects, (
        f"Expected projects {expected_projects}, got {actual_projects}"
    )


def test_api_query_e102():
    """Test the POST /query endpoint for employee E102."""
    expected_projects = {"Project Titan"}
    actual_projects = set(query_api("E102"))
    assert actual_projects == expected_projects, (
        f"Expected projects {expected_projects}, got {actual_projects}"
    )


def extract_expected_from_image():
    proc = subprocess.run(
        ["tesseract", "/app/legacy_export.png", "stdout"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, f"tesseract failed: {proc.stderr}"
    nodes = {}
    edges = []
    node_re = re.compile(
        r'Node:\s*([A-Za-z_][A-Za-z0-9_]*)\s*\|\s*id:\s*([A-Za-z0-9_]+)\s*,\s*name:\s*"([^"]+)"'
    )
    edge_re = re.compile(
        r'Edge:\s*([A-Za-z_][A-Za-z0-9_]*)\s*\|\s*from:\s*([A-Za-z0-9_]+)\s*,\s*to:\s*([A-Za-z0-9_]+)'
    )
    for line in proc.stdout.splitlines():
        nm = node_re.search(line)
        if nm:
            label, identifier, name = nm.groups()
            nodes.setdefault(label, []).append({"id": identifier, "name": name})
        em = edge_re.search(line)
        if em:
            rel, source, target = em.groups()
            edges.append({"rel": rel, "from": source, "to": target})
    assert nodes and edges, f"Could not parse OCR output: {proc.stdout!r}"
    assert "Employee" in nodes and "Project" in nodes
    return {"nodes": nodes, "edges": edges, "ocr": proc.stdout}


def listener_pids(port=8080):
    inodes = set()
    for netfile in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(netfile).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) < 10 or fields[3] != "0A":
                continue
            try:
                local_port = int(fields[1].rsplit(":", 1)[1], 16)
            except (ValueError, IndexError):
                continue
            if local_port == port:
                inodes.add(fields[9])
    found = set()
    for procdir in Path("/proc").glob("[0-9]*"):
        try:
            for fd in (procdir / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                m = re.fullmatch(r"socket:\[(\d+)\]", target)
                if m and m.group(1) in inodes:
                    found.add(int(procdir.name))
                    break
        except OSError:
            continue
    return found


def process_details(pid):
    raw_cmd = Path(f"/proc/{pid}/cmdline").read_bytes().split(b"\0")
    cmd = [x.decode("utf-8", "surrogateescape") for x in raw_cmd if x]
    assert cmd, f"Could not determine command line for API process {pid}"
    cwd = os.readlink(f"/proc/{pid}/cwd")
    env = os.environ.copy()
    try:
        entries = Path(f"/proc/{pid}/environ").read_bytes().split(b"\0")
        for entry in entries:
            if b"=" in entry:
                k, v = entry.split(b"=", 1)
                env[k.decode("utf-8", "ignore")] = v.decode("utf-8", "surrogateescape")
    except OSError:
        pass
    return cmd, cwd, env


def find_kuzu_python(cmd, env, cwd):
    candidates = []
    first = cmd[0]
    if "python" in os.path.basename(first).lower():
        candidates.append(first)
    parent = os.path.dirname(first)
    if parent:
        candidates.extend([os.path.join(parent, "python3"), os.path.join(parent, "python")])
    candidates.extend(["python3", "python"])
    seen = set()
    for candidate in candidates:
        if candidate in seen:
            continue
        seen.add(candidate)
        try:
            result = subprocess.run(
                [candidate, "-c", "import kuzu"],
                cwd=cwd,
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=15,
            )
            if result.returncode == 0:
                return candidate
        except (OSError, subprocess.TimeoutExpired):
            pass
    pytest.fail("The API environment has no usable Kùzu Python installation")


def stop_listener():
    for sig, attempts in ((signal.SIGTERM, 30), (signal.SIGKILL, 20)):
        for _ in range(attempts):
            pids = listener_pids()
            if not pids:
                return
            for pid in pids:
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
            time.sleep(0.1)
    assert not listener_pids(), "Could not stop the submitted API to inspect its database"


def start_service(cmd, cwd, env):
    log = open("/home/user/api.log", "ab", buffering=0)
    try:
        subprocess.Popen(
            cmd,
            cwd=cwd,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=log,
            start_new_session=True,
            close_fds=True,
        )
    finally:
        log.close()


def wait_for_api(seconds=20):
    deadline = time.time() + seconds
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.post(URL, json={"employee_id": "__healthcheck__"}, timeout=1)
            if response.status_code == 200:
                return
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.25)
    pytest.fail(f"API did not restart on 127.0.0.1:8080: {last_error}")


def test_real_kuzu_database_and_database_backed_api():
    expected = extract_expected_from_image()
    pids = listener_pids()
    assert pids, "No process is listening on 127.0.0.1:8080"
    pid = min(pids)
    cmd, cwd, env = process_details(pid)
    python = find_kuzu_python(cmd, env, cwd)

    token = uuid.uuid4().hex[:12].upper()
    mutation = {
        "employee_id": "EV" + token,
        "employee_name": "Verifier Employee " + token,
        "project_id": "PV" + token,
        "project_name": "Verifier Project " + token,
    }
    Path("/tmp/expected_graph.json").write_text(json.dumps(expected))
    Path("/tmp/mutation.json").write_text(json.dumps(mutation))

    helper = r'''
import json
import kuzu

expected = json.load(open('/tmp/expected_graph.json'))
mutation = json.load(open('/tmp/mutation.json'))

def all_rows(result):
    rows = []
    while result.has_next():
        rows.append(result.get_next())
    return rows

def safe_ident(value):
    assert value and value.replace('_', '').isalnum() and not value[0].isdigit()
    return value

db = kuzu.Database('/home/user/graph_db')
conn = kuzu.Connection(db)

employee_label = safe_ident('Employee')
project_label = safe_ident('Project')
rel_label = safe_ident('WORKS_ON')

employees = all_rows(conn.execute(
    'MATCH (e:Employee) RETURN e.id, e.name ORDER BY e.id'))
projects = all_rows(conn.execute(
    'MATCH (p:Project) RETURN p.id, p.name ORDER BY p.id'))
relationships = all_rows(conn.execute(
    'MATCH (e:Employee)-[:WORKS_ON]->(p:Project) RETURN e.id, p.id ORDER BY e.id, p.id'))

want_employees = sorted([[x['id'], x['name']] for x in expected['nodes']['Employee']])
want_projects = sorted([[x['id'], x['name']] for x in expected['nodes']['Project']])
want_edges = sorted([[x['from'], x['to']] for x in expected['edges'] if x['rel'] == 'WORKS_ON'])
assert sorted(employees) == want_employees, (employees, want_employees)
assert sorted(projects) == want_projects, (projects, want_projects)
assert sorted(relationships) == want_edges, (relationships, want_edges)

# In Kùzu, a node-table primary key has an automatically maintained primary-key index.
for table in ('Employee', 'Project'):
    result = conn.execute("CALL table_info('" + table + "') RETURN *")
    columns = [str(x).lower().replace('_', ' ') for x in result.get_column_names()]
    rows = all_rows(result)
    name_col = next((i for i, x in enumerate(columns) if x in ('name', 'property name')), None)
    pk_col = next((i for i, x in enumerate(columns) if 'primary' in x and 'key' in x), None)
    assert name_col is not None and pk_col is not None, (table, columns, rows)
    id_rows = [row for row in rows if str(row[name_col]) == 'id']
    assert id_rows, (table, columns, rows)
    assert str(id_rows[0][pk_col]).lower() in ('true', '1'), (table, columns, id_rows[0])

# Add values unknown when the submission was built. The restarted API must retrieve
# this relationship from the submitted database rather than a fixed response table.
conn.execute('CREATE (e:Employee {id: $id, name: $name})',
             {'id': mutation['employee_id'], 'name': mutation['employee_name']})
conn.execute('CREATE (p:Project {id: $id, name: $name})',
             {'id': mutation['project_id'], 'name': mutation['project_name']})
conn.execute('MATCH (e:Employee {id: $eid}), (p:Project {id: $pid}) CREATE (e)-[:WORKS_ON]->(p)',
             {'eid': mutation['employee_id'], 'pid': mutation['project_id']})
print(json.dumps({'ok': True}))
'''
    Path("/tmp/check_and_mutate_kuzu.py").write_text(helper)

    stop_listener()
    result = subprocess.run(
        [python, "/tmp/check_and_mutate_kuzu.py"],
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=45,
    )
    start_service(cmd, cwd, env)
    wait_for_api()

    assert result.returncode == 0, (
        "Kùzu database validation failed.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    actual = query_api(mutation["employee_id"])
    assert actual == [mutation["project_name"]], (
        "API did not return the project inserted into the submitted Kùzu database; "
        f"expected {[mutation['project_name']]}, got {actual}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
