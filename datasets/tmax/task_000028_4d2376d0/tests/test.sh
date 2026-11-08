#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import ast
import json
import os
import re
import sqlite3
import subprocess
import sys
import time
import urllib.parse
import urllib.request
import uuid

HOME = "/home/user"
SCRIPT = os.path.join(HOME, "analyze.py")
OUTPUT = os.path.join(HOME, "critical_failures.json")
DB = os.path.join(HOME, "backups.db")
TTL = os.path.join(HOME, "architecture.ttl")
LOG = "/tmp/sparqlwrapper_calls.jsonl"
RUNNER = "/tmp/run_analyze_instrumented.py"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def fuseki_process_running():
    me = os.getpid()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == me:
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                cmd = f.read().replace(b"\0", b" ").decode("utf-8", "ignore").lower()
            if "fuseki" in cmd:
                return True
        except (OSError, PermissionError):
            pass
    return False


def request(url, data=None, method=None, content_type=None, timeout=10):
    headers = {}
    if content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.read()


def wait_for_fuseki():
    deadline = time.time() + 15
    last_error = None
    while time.time() < deadline:
        try:
            query = urllib.parse.urlencode({"query": "ASK { ?s ?p ?o }"})
            raw = request("http://127.0.0.1:3030/ds/query?" + query)
            parsed = json.loads(raw.decode("utf-8"))
            require("boolean" in parsed, "Fuseki query endpoint did not return an ASK result")
            return
        except Exception as exc:
            last_error = exc
            time.sleep(0.5)
    raise AssertionError(f"Fuseki dataset /ds is not reachable on port 3030: {last_error}")


def upload_graph(ttl_text):
    update = urllib.parse.urlencode({"update": "CLEAR ALL"}).encode()
    request("http://127.0.0.1:3030/ds/update", update, "POST", "application/x-www-form-urlencoded")
    request("http://127.0.0.1:3030/ds/data?default", ttl_text.encode(), "PUT", "text/turtle")

    query = urllib.parse.urlencode({"query": "ASK { ?s <http://example.org/dependsOn> ?o }"})
    result = json.loads(request("http://127.0.0.1:3030/ds/query?" + query).decode())
    require(result.get("boolean") is True, "Uploaded RDF graph is not queryable in Fuseki")


def write_database(datastores, backups):
    if os.path.exists(DB):
        os.remove(DB)
    conn = sqlite3.connect(DB)
    try:
        conn.execute("CREATE TABLE datastores (id INTEGER PRIMARY KEY, name TEXT, uri TEXT)")
        conn.execute("CREATE TABLE backups (id INTEGER PRIMARY KEY, datastore_id INTEGER, timestamp DATETIME, status TEXT, size_bytes INTEGER)")
        conn.executemany("INSERT INTO datastores VALUES (?, ?, ?)", datastores)
        conn.executemany("INSERT INTO backups VALUES (?, ?, ?, ?, ?)", backups)
        conn.commit()
    finally:
        conn.close()


def expected_from_fixture(datastores, backups, edges):
    expected = {}
    for ds_id, name, uri in datastores:
        own = [b for b in backups if b[1] == ds_id]
        if not own:
            continue
        latest = max(own, key=lambda row: row[2])
        if latest[3] != "FAILED":
            continue
        successful = [b[4] for b in own if b[3] == "SUCCESS"]
        average = float(sum(successful) / len(successful)) if successful else 0.0

        impacted = set()
        frontier = [uri]
        while frontier:
            target = frontier.pop()
            for subject, obj in edges:
                if obj == target and subject not in impacted:
                    impacted.add(subject)
                    frontier.append(subject)
        expected[name] = {
            "avg_successful_size": average,
            "impacted_services": sorted(impacted),
        }
    return expected


def validate_output(expected):
    require(os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing")
    try:
        with open(OUTPUT, encoding="utf-8") as f:
            actual = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"File {OUTPUT} is not valid JSON: {exc}")

    require(isinstance(actual, dict), "Top-level JSON value must be an object")
    require(set(actual.keys()) == set(expected.keys()),
            f"The set of failing datastores does not match. Expected {sorted(expected)}, got {sorted(actual)}")

    for name, actual_data in actual.items():
        require(isinstance(actual_data, dict), f"Entry for {name} must be an object")
        require("avg_successful_size" in actual_data, f"Missing avg_successful_size for {name}")
        require(isinstance(actual_data["avg_successful_size"], (int, float)) and not isinstance(actual_data["avg_successful_size"], bool),
                f"avg_successful_size must be numeric for {name}")
        require(abs(actual_data["avg_successful_size"] - expected[name]["avg_successful_size"]) < 0.1,
                f"Incorrect average for {name}")
        require("impacted_services" in actual_data, f"Missing impacted_services for {name}")
        impacted = actual_data["impacted_services"]
        require(isinstance(impacted, list), f"impacted_services must be a list for {name}")
        require(impacted == sorted(impacted), f"impacted_services must be sorted alphabetically for {name}")
        require(impacted == expected[name]["impacted_services"],
                f"Incorrect impacted services for {name}. Expected {expected[name]['impacted_services']}, got {impacted}")
    return actual


def run_analyze(failing_uris):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    if os.path.exists(LOG):
        os.remove(LOG)

    completed = subprocess.run(
        [sys.executable, RUNNER, SCRIPT, LOG],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=45,
    )
    require(completed.returncode == 0,
            "analyze.py failed when executed:\nSTDOUT:\n" + completed.stdout + "\nSTDERR:\n" + completed.stderr)

    calls = []
    if os.path.isfile(LOG):
        with open(LOG, encoding="utf-8") as f:
            for line in f:
                try:
                    calls.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    executed_queries = [c.get("query", "") for c in calls if c.get("event") in ("query", "queryAndConvert")]
    require(executed_queries, "analyze.py did not execute a query through SPARQLWrapper")
    for uri in failing_uris:
        require(any(uri in query for query in executed_queries),
                f"No executed parameterized SPARQLWrapper query contained failing datastore URI {uri}")
    require(any("dependsOn" in query for query in executed_queries),
            "Executed SPARQL queries do not use the dependsOn predicate")


require(os.path.isfile(SCRIPT), "/home/user/analyze.py is missing or is not a regular file")
with open(SCRIPT, encoding="utf-8") as f:
    source = f.read()
require(source.strip(), "analyze.py is empty")
try:
    tree = ast.parse(source, filename=SCRIPT)
except SyntaxError as exc:
    raise AssertionError(f"analyze.py is not valid Python: {exc}")

require(any(isinstance(node, (ast.Import, ast.ImportFrom)) and
            ((isinstance(node, ast.ImportFrom) and node.module == "SPARQLWrapper") or
             (isinstance(node, ast.Import) and any(alias.name == "SPARQLWrapper" for alias in node.names)))
            for node in ast.walk(tree)),
        "analyze.py must import and use the SPARQLWrapper library")

string_text = "\n".join(node.value for node in ast.walk(tree)
                         if isinstance(node, ast.Constant) and isinstance(node.value, str)).upper()
require("SELECT" in string_text and "BACKUPS" in string_text and "DATASTORES" in string_text,
        "analyze.py must query both SQLite tables")
require(string_text.count("SELECT") >= 2 or re.search(r"\bOVER\s*\(", string_text),
        "The SQLite lookup must use a subquery or window function to determine the latest backup")

require(fuseki_process_running(), "No Apache Jena Fuseki server process is running")
wait_for_fuseki()

with open(RUNNER, "w", encoding="utf-8") as f:
    f.write(r'''import json
import runpy
import sys
import SPARQLWrapper as module

script, log_path = sys.argv[1], sys.argv[2]
RealSPARQLWrapper = module.SPARQLWrapper

class LoggedSPARQLWrapper(RealSPARQLWrapper):
    def _record(self, event):
        with open(log_path, "a", encoding="utf-8") as out:
            out.write(json.dumps({"event": event, "query": getattr(self, "queryString", "")}) + "\n")

    def setQuery(self, query):
        result = super().setQuery(query)
        self._record("setQuery")
        return result

    def query(self, *args, **kwargs):
        self._record("query")
        return super().query(*args, **kwargs)

    def queryAndConvert(self, *args, **kwargs):
        self._record("queryAndConvert")
        return super().queryAndConvert(*args, **kwargs)

module.SPARQLWrapper = LoggedSPARQLWrapper
runpy.run_path(script, run_name="__main__")
''')

# Recreate and test the original supplied fixture, so the original assertions remain enforced.
original_datastores = [
    (1, "users_db", "http://example.org/UsersDB"),
    (2, "orders_db", "http://example.org/OrdersDB"),
    (3, "logs_db", "http://example.org/LogsDB"),
]
original_backups = [
    (1, 1, "2023-10-01 10:00:00", "SUCCESS", 5000),
    (2, 1, "2023-10-02 10:00:00", "SUCCESS", 5200),
    (3, 1, "2023-10-03 10:00:00", "FAILED", 0),
    (4, 2, "2023-10-01 11:00:00", "SUCCESS", 10000),
    (5, 2, "2023-10-02 11:00:00", "SUCCESS", 11000),
    (6, 3, "2023-10-01 12:00:00", "FAILED", 0),
    (7, 3, "2023-10-02 12:00:00", "FAILED", 0),
]
original_edges = [
    ("http://example.org/AuthService", "http://example.org/UsersDB"),
    ("http://example.org/BillingService", "http://example.org/AuthService"),
    ("http://example.org/BillingService", "http://example.org/OrdersDB"),
    ("http://example.org/ReportingService", "http://example.org/BillingService"),
    ("http://example.org/ReportingService", "http://example.org/LogsDB"),
    ("http://example.org/Frontend", "http://example.org/AuthService"),
    ("http://example.org/Frontend", "http://example.org/ReportingService"),
]
original_ttl = "@prefix ex: <http://example.org/> .\n" + "\n".join(
    f"<{s}> <http://example.org/dependsOn> <{o}> ." for s, o in original_edges
) + "\n"
write_database(original_datastores, original_backups)
with open(TTL, "w", encoding="utf-8") as f:
    f.write(original_ttl)
upload_graph(original_ttl)
original_expected = expected_from_fixture(original_datastores, original_backups, original_edges)
run_analyze(["http://example.org/UsersDB", "http://example.org/LogsDB"])
original_actual = validate_output(original_expected)
require(original_actual["users_db"]["impacted_services"] == [
    "http://example.org/AuthService", "http://example.org/BillingService",
    "http://example.org/Frontend", "http://example.org/ReportingService"
], "Original users_db transitive dependency assertion failed")
require(original_actual["logs_db"]["impacted_services"] == [
    "http://example.org/Frontend", "http://example.org/ReportingService"
], "Original logs_db transitive dependency assertion failed")

# Exercise the submitted script again on unpredictable data and RDF, preventing hardcoded output.
token = uuid.uuid4().hex
base = f"http://verification.example/{token}/"
dynamic_datastores = [
    (11, f"primary_{token}", base + "PrimaryStore"),
    (22, f"healthy_{token}", base + "HealthyStore"),
    (33, f"empty_history_{token}", base + "EmptyHistoryStore"),
]
dynamic_backups = [
    (101, 11, "2041-01-01 01:00:00", "SUCCESS", 137),
    (102, 11, "2041-01-02 01:00:00", "SUCCESS", 424),
    (103, 11, "2041-01-03 01:00:00", "FAILED", 0),
    (201, 22, "2041-02-01 01:00:00", "FAILED", 0),
    (202, 22, "2041-02-02 01:00:00", "SUCCESS", 911),
    (301, 33, "2041-03-01 01:00:00", "FAILED", 0),
]
s1, s2, s3, s4, s5 = [base + name for name in ("SvcA", "SvcB", "SvcC", "SvcD", "SvcE")]
dynamic_edges = [
    (s1, base + "PrimaryStore"),
    (s2, s1),
    (s3, s2),
    (s4, s3),
    (s4, base + "HealthyStore"),
    (s5, base + "EmptyHistoryStore"),
]
dynamic_ttl = "\n".join(f"<{s}> <http://example.org/dependsOn> <{o}> ." for s, o in dynamic_edges) + "\n"
write_database(dynamic_datastores, dynamic_backups)
with open(TTL, "w", encoding="utf-8") as f:
    f.write(dynamic_ttl)
upload_graph(dynamic_ttl)
dynamic_expected = expected_from_fixture(dynamic_datastores, dynamic_backups, dynamic_edges)
run_analyze([base + "PrimaryStore", base + "EmptyHistoryStore"])
validate_output(dynamic_expected)
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
