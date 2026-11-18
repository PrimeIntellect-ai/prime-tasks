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
set +e
mkdir -p /logs/verifier

service postgresql start >/dev/null 2>&1 || true
neo4j start >/dev/null 2>&1 || true
sleep 3

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import time
from pathlib import Path

import psycopg2
import pytest
import requests
from neo4j import GraphDatabase

BASE_URL = "http://127.0.0.1:8080"
AUTH_HEADER = {"Authorization": "Bearer super-secret-etl-token"}

SUFFIX = secrets.randbelow(800000) + 100000
DYNAMIC_DEPARTMENT_ID = SUFFIX
DYNAMIC_DEPARTMENT = f"Verification-{secrets.token_hex(6)}"
DYNAMIC_ROOT = SUFFIX * 10 + 1
DYNAMIC_MANAGER = SUFFIX * 10 + 2
DYNAMIC_LEAF_1 = SUFFIX * 10 + 3
DYNAMIC_LEAF_2 = SUFFIX * 10 + 4
DYNAMIC_SALARY = secrets.randbelow(70000) + 130001
TEMP_REPORT = SUFFIX * 10 + 9
GRAPH = None


def _seed_postgres():
    conn = psycopg2.connect(
        host="127.0.0.1", port=5432, dbname="corp_data",
        user="postgres", password="postgres"
    )
    conn.autocommit = True
    try:
        with conn.cursor() as cur:
            cur.execute("DROP TABLE IF EXISTS employees CASCADE")
            cur.execute("DROP TABLE IF EXISTS departments CASCADE")
            cur.execute("""
                CREATE TABLE departments (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL
                )
            """)
            cur.execute("""
                CREATE TABLE employees (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    manager_id INTEGER REFERENCES employees(id),
                    department_id INTEGER NOT NULL REFERENCES departments(id),
                    salary INTEGER NOT NULL
                )
            """)
            cur.executemany(
                "INSERT INTO departments (id, name) VALUES (%s, %s)",
                [(1, "Engineering"), (2, "Executive"),
                 (DYNAMIC_DEPARTMENT_ID, DYNAMIC_DEPARTMENT)],
            )
            cur.executemany(
                """INSERT INTO employees
                   (id, name, manager_id, department_id, salary)
                   VALUES (%s, %s, %s, %s, %s)""",
                [
                    (1, "Chief Executive", None, 2, 200000),
                    (2, "Engineering Manager", 1, 1, 120000),
                    (3, "Engineer Three", 2, 1, 90000),
                    (4, "Engineer Four", 2, 1, 91000),
                    (5, "Engineer Five", 2, 1, 92000),
                    (DYNAMIC_ROOT, "Dynamic Root", None,
                     DYNAMIC_DEPARTMENT_ID, DYNAMIC_SALARY + 20000),
                    (DYNAMIC_MANAGER, "Dynamic Manager", DYNAMIC_ROOT,
                     DYNAMIC_DEPARTMENT_ID, DYNAMIC_SALARY),
                    (DYNAMIC_LEAF_1, "Dynamic Leaf One", DYNAMIC_MANAGER,
                     DYNAMIC_DEPARTMENT_ID, DYNAMIC_SALARY - 10000),
                    (DYNAMIC_LEAF_2, "Dynamic Leaf Two", DYNAMIC_MANAGER,
                     DYNAMIC_DEPARTMENT_ID, DYNAMIC_SALARY - 11000),
                ],
            )
    finally:
        conn.close()


def _env_file_values():
    result = {}
    env_path = Path("/app/api/.env")
    if env_path.is_file():
        for raw in env_path.read_text(errors="ignore").splitlines():
            raw = raw.strip()
            if not raw or raw.startswith("#") or "=" not in raw:
                continue
            key, value = raw.split("=", 1)
            result[key.strip()] = value.strip().strip("'\"")
    return result


def _connect_neo4j():
    values = _env_file_values()
    uris = []
    users = []
    passwords = []
    for key, value in {**os.environ, **values}.items():
        upper = key.upper()
        if "NEO4J" in upper and ("URI" in upper or "URL" in upper):
            uris.append(value)
        if "NEO4J" in upper and ("USER" in upper or "USERNAME" in upper):
            users.append(value)
        if "NEO4J" in upper and "PASSWORD" in upper:
            passwords.append(value)

    for source_path in ("/home/user/etl_pipeline.py", "/app/api/main.py"):
        try:
            source = Path(source_path).read_text(errors="ignore")
        except OSError:
            continue
        uris.extend(re.findall(r'["\'](bolt(?:\+s)?://[^"\']+)["\']', source))
        passwords.extend(re.findall(
            r'(?i)password\s*=\s*["\']([^"\']+)["\']', source
        ))
        users.extend(re.findall(
            r'(?i)(?:user|username)\s*=\s*["\']([^"\']+)["\']', source
        ))

    uris.extend(["bolt://127.0.0.1:7687", "bolt://localhost:7687"])
    users.extend(["neo4j"])
    passwords.extend(["password", "neo4j"])

    attempts = []
    for uri in dict.fromkeys(uris):
        attempts.append((uri, None))
        for user in dict.fromkeys(users):
            for password in dict.fromkeys(passwords):
                attempts.append((uri, (user, password)))

    last_error = None
    for uri, auth in attempts:
        driver = None
        try:
            driver = GraphDatabase.driver(uri, auth=auth)
            driver.verify_connectivity()
            return driver
        except Exception as exc:
            last_error = exc
            if driver is not None:
                driver.close()
    raise AssertionError(f"Could not connect to populated Neo4j database: {last_error}")


def _node_predicate(alias, parameter):
    return (
        f"any(k IN keys({alias}) WHERE "
        f"toString({alias}[k]) = toString(${parameter}))"
    )


def _graph_has_dynamic_path(driver):
    query = f"""
        MATCH (leaf:Employee)-[:REPORTS_TO]->(manager:Employee)
              -[:REPORTS_TO]->(root:Employee)
        WHERE {_node_predicate('leaf', 'leaf')}
          AND {_node_predicate('manager', 'manager')}
          AND {_node_predicate('root', 'root')}
        RETURN count(*) AS paths
    """
    with driver.session() as session:
        return session.run(
            query, leaf=DYNAMIC_LEAF_1,
            manager=DYNAMIC_MANAGER, root=DYNAMIC_ROOT
        ).single()["paths"] > 0


@pytest.fixture(scope="session", autouse=True)
def prepare_and_execute_submission():
    global GRAPH

    etl_path = Path("/home/user/etl_pipeline.py")
    assert etl_path.is_file(), "Missing /home/user/etl_pipeline.py"
    assert not etl_path.is_symlink(), "ETL pipeline must be a regular submitted script"
    etl_source = etl_path.read_text(errors="ignore")
    assert re.search(r"\bWITH\s+RECURSIVE\b", etl_source, re.I), \
        "ETL pipeline does not contain a recursive CTE"
    assert re.search(r"\bREPORTS_TO\b", etl_source, re.I), \
        "ETL pipeline does not create REPORTS_TO relationships"
    assert re.search(r"\$[A-Za-z_][A-Za-z0-9_]*", etl_source), \
        "ETL Cypher does not use parameters"
    assert re.search(r"\.(?:run|execute_query)\s*\(", etl_source), \
        "ETL pipeline does not execute a database query"

    api_path = Path("/app/api/main.py")
    assert api_path.is_file(), "Missing /app/api/main.py"
    api_source = api_path.read_text(errors="ignore")
    assert re.search(r"\bJOIN\b", api_source, re.I), \
        "Cross-reference implementation does not contain the required SQL join"
    assert re.search(r"\bMATCH\b", api_source, re.I), \
        "API implementation does not contain a Cypher query"
    assert "REPORTS_TO" in api_source, \
        "API implementation does not query REPORTS_TO relationships"

    _seed_postgres()
    completed = subprocess.run(
        ["python3", str(etl_path)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert completed.returncode == 0, \
        f"ETL pipeline failed when executed on verifier data:\n{completed.stdout}"

    GRAPH = _connect_neo4j()
    assert _graph_has_dynamic_path(GRAPH), \
        "Executed ETL did not load the dynamic employee hierarchy into Neo4j"
    yield
    if GRAPH is not None:
        GRAPH.close()


def _get(path, headers=AUTH_HEADER):
    try:
        return requests.get(
            f"{BASE_URL}{path}", headers=headers, timeout=5,
            params={"verification_nonce": secrets.token_hex(6)},
        )
    except requests.exceptions.ConnectionError:
        pytest.fail(
            "FastAPI application is not running or not listening on 127.0.0.1:8080."
        )


def test_api_unauthorized_access():
    response = _get("/api/v1/hierarchy/5", headers={})
    assert response.status_code == 401, \
        f"Expected HTTP 401 Unauthorized, got {response.status_code}. Response: {response.text}"
    invalid = _get(
        "/api/v1/hierarchy/5",
        headers={"Authorization": "Bearer wrong-token"},
    )
    assert invalid.status_code == 401, \
        f"Expected invalid bearer token to return 401, got {invalid.status_code}"


def test_api_hierarchy_endpoint():
    response = _get("/api/v1/hierarchy/5")
    assert response.status_code == 200, \
        f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert "employee_id" in data, "Response missing 'employee_id' key."
    assert "management_chain" in data, "Response missing 'management_chain' key."
    assert data["employee_id"] == 5, \
        f"Expected employee_id 5, got {data['employee_id']}"
    assert data["management_chain"] == [2, 1], \
        f"Expected management_chain [2, 1], got {data['management_chain']}"


def test_api_cross_reference_endpoint():
    response = _get("/api/v1/cross-reference/2")
    assert response.status_code == 200, \
        f"Expected HTTP 200 OK, got {response.status_code}. Response: {response.text}"
    data = response.json()
    assert data.get("employee_id") == 2, \
        f"Expected employee_id 2, got {data.get('employee_id')}"
    assert data.get("department") == "Engineering", \
        f"Expected department 'Engineering', got {data.get('department')}"
    assert data.get("salary") == 120000, \
        f"Expected salary 120000, got {data.get('salary')}"
    assert data.get("direct_reports_count") == 3, \
        f"Expected direct_reports_count 3, got {data.get('direct_reports_count')}"


def test_dynamic_hierarchy_from_neo4j():
    response = _get(f"/api/v1/hierarchy/{DYNAMIC_LEAF_1}")
    assert response.status_code == 200, response.text
    data = response.json()
    assert data.get("employee_id") == DYNAMIC_LEAF_1
    assert data.get("management_chain") == [DYNAMIC_MANAGER, DYNAMIC_ROOT]

    delete_query = f"""
        MATCH (manager:Employee)-[r:REPORTS_TO]->(root:Employee)
        WHERE {_node_predicate('manager', 'manager')}
          AND {_node_predicate('root', 'root')}
        WITH r DELETE r RETURN count(*) AS removed
    """
    restore_query = f"""
        MATCH (manager:Employee), (root:Employee)
        WHERE {_node_predicate('manager', 'manager')}
          AND {_node_predicate('root', 'root')}
        CREATE (manager)-[:REPORTS_TO]->(root)
    """
    with GRAPH.session() as session:
        removed = session.run(
            delete_query, manager=DYNAMIC_MANAGER, root=DYNAMIC_ROOT
        ).single()["removed"]
    assert removed > 0
    try:
        changed = _get(f"/api/v1/hierarchy/{DYNAMIC_LEAF_1}")
        assert changed.status_code == 200, changed.text
        assert changed.json().get("management_chain") == [DYNAMIC_MANAGER], \
            "Hierarchy endpoint did not reflect a live Neo4j relationship change"
    finally:
        with GRAPH.session() as session:
            session.run(
                restore_query, manager=DYNAMIC_MANAGER, root=DYNAMIC_ROOT
            ).consume()


def test_dynamic_cross_reference_uses_both_databases():
    response = _get(f"/api/v1/cross-reference/{DYNAMIC_MANAGER}")
    assert response.status_code == 200, response.text
    data = response.json()
    assert data.get("employee_id") == DYNAMIC_MANAGER
    assert data.get("department") == DYNAMIC_DEPARTMENT
    assert data.get("salary") == DYNAMIC_SALARY
    assert data.get("direct_reports_count") == 2

    create_query = f"""
        MATCH (manager:Employee)
        WHERE {_node_predicate('manager', 'manager')}
        CREATE (temp:Employee {{id: $temp}})-[:REPORTS_TO]->(manager)
    """
    cleanup_query = "MATCH (temp:Employee {id: $temp}) DETACH DELETE temp"
    with GRAPH.session() as session:
        session.run(
            create_query, manager=DYNAMIC_MANAGER, temp=TEMP_REPORT
        ).consume()
    try:
        changed = _get(f"/api/v1/cross-reference/{DYNAMIC_MANAGER}")
        assert changed.status_code == 200, changed.text
        changed_data = changed.json()
        assert changed_data.get("department") == DYNAMIC_DEPARTMENT
        assert changed_data.get("salary") == DYNAMIC_SALARY
        assert changed_data.get("direct_reports_count") == 3, \
            "Cross-reference endpoint did not reflect a live Neo4j graph change"
    finally:
        with GRAPH.session() as session:
            session.run(cleanup_query, temp=TEMP_REPORT).consume()


def test_startup_log_file_exists():
    log_path = "/home/user/api_startup.log"
    assert os.path.isfile(log_path), f"The log file {log_path} does not exist."
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
