#!/bin/bash
set -e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import subprocess
import time
import urllib.request
import uuid

SCRIPT = "/home/user/get_dependencies.sh"
OUTPUT = "/home/user/output.txt"
ENDPOINT = "http://localhost:7474/db/neo4j/tx/commit"
CURL_LOG = "/tmp/verifier_curl_calls.jsonl"
WRAPPER_DIR = "/tmp/verifier-bin"


def neo4j_request(statement, parameters=None, retries=1):
    payload = json.dumps({"statements": [{
        "statement": statement,
        "parameters": parameters or {},
        "resultDataContents": ["row"],
    }]}).encode()
    last_error = None
    for _ in range(retries):
        try:
            req = urllib.request.Request(
                ENDPOINT,
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=5) as response:
                result = json.loads(response.read().decode())
            assert not result.get("errors"), f"Neo4j returned errors: {result.get('errors')}"
            return result
        except Exception as exc:
            last_error = exc
            time.sleep(1)
    raise AssertionError(f"Neo4j HTTP API was not ready: {last_error}")


def install_curl_wrapper():
    os.makedirs(WRAPPER_DIR, exist_ok=True)
    wrapper = os.path.join(WRAPPER_DIR, "curl")
    code = r'''#!/usr/bin/python3
import json
import os
import subprocess
import sys

args = sys.argv[1:]
bodies = []
stdin_data = None
data_options = {"-d", "--data", "--data-raw", "--data-binary", "--data-urlencode", "--json"}
i = 0
while i < len(args):
    arg = args[i]
    value = None
    if arg in data_options and i + 1 < len(args):
        value = args[i + 1]
        i += 1
    else:
        for option in data_options:
            if arg.startswith(option + "="):
                value = arg.split("=", 1)[1]
                break
    if value is not None:
        if value == "@-":
            if stdin_data is None:
                stdin_data = sys.stdin.buffer.read()
            bodies.append(stdin_data.decode("utf-8", "replace"))
        elif value.startswith("@"):
            try:
                with open(value[1:], "rb") as f:
                    bodies.append(f.read().decode("utf-8", "replace"))
            except OSError:
                bodies.append(value)
        else:
            bodies.append(value)
    i += 1

with open(os.environ["VERIFIER_CURL_LOG"], "a") as f:
    f.write(json.dumps({"args": args, "bodies": bodies}) + "\n")

result = subprocess.run(["/usr/bin/curl"] + args, input=stdin_data)
sys.exit(result.returncode)
'''
    with open(wrapper, "w") as f:
        f.write(code)
    os.chmod(wrapper, 0o755)


def read_curl_calls():
    if not os.path.exists(CURL_LOG):
        return []
    calls = []
    with open(CURL_LOG) as f:
        for line in f:
            if line.strip():
                calls.append(json.loads(line))
    return calls


def recursive_objects(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from recursive_objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from recursive_objects(child)


def assert_parameterized_api_call(paper_id):
    calls = read_curl_calls()
    matching_endpoint_calls = [
        call for call in calls
        if any(ENDPOINT == arg or ENDPOINT in arg for arg in call.get("args", []))
    ]
    assert matching_endpoint_calls, "Script did not invoke curl for the required Neo4j HTTP endpoint."

    for call in matching_endpoint_calls:
        for body in call.get("bodies", []):
            try:
                payload = json.loads(body)
            except (TypeError, json.JSONDecodeError):
                continue
            for obj in recursive_objects(payload):
                statement = obj.get("statement")
                parameters = obj.get("parameters")
                if not isinstance(statement, str) or not isinstance(parameters, dict):
                    continue
                keys = [key for key, value in parameters.items() if value == paper_id]
                if not keys:
                    continue
                if not any(re.search(r"\$" + re.escape(str(key)) + r"\b", statement) for key in keys):
                    continue
                if "CITES" not in statement.upper():
                    continue
                # Accept the standard variable-length syntax and Neo4j 5 quantified syntax.
                bounded = (
                    re.search(r"\*\s*(?:1\s*)?\.\.\s*3", statement)
                    or re.search(r"\{\s*1\s*,\s*3\s*\}", statement)
                )
                if bounded:
                    return
    raise AssertionError(
        "No curl request contained a parameterized CITES query bounded to three hops "
        f"with the supplied Paper ID {paper_id!r}."
    )


def run_script_and_check(paper_id, expected):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    if os.path.exists(CURL_LOG):
        os.remove(CURL_LOG)

    env = os.environ.copy()
    env["PATH"] = WRAPPER_DIR + os.pathsep + env.get("PATH", "")
    env["VERIFIER_CURL_LOG"] = CURL_LOG
    result = subprocess.run(
        [SCRIPT, paper_id], capture_output=True, text=True, env=env, timeout=30
    )
    assert result.returncode == 0, f"Script execution failed with error: {result.stderr}"
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} was not created."
    with open(OUTPUT) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines == expected, f"Output file content {lines} does not match expected {expected}."
    assert_parameterized_api_call(paper_id)


def test_container_running():
    result = subprocess.run(
        ["docker", "ps", "--filter", "name=research_graph", "--format", "{{.Names}}"],
        capture_output=True, text=True
    )
    assert "research_graph" in result.stdout, "Container 'research_graph' is not running."

    inspected = subprocess.run(
        ["docker", "inspect", "research_graph"], capture_output=True, text=True
    )
    assert inspected.returncode == 0, "Could not inspect container 'research_graph'."
    info = json.loads(inspected.stdout)[0]
    assert info["State"]["Running"], "Container 'research_graph' is not running."
    env = info["Config"].get("Env", [])
    assert "NEO4J_AUTH=none" in env, "Neo4j authentication was not disabled."
    bindings = info["HostConfig"].get("PortBindings") or {}
    assert any(x.get("HostPort") == "7474" for x in bindings.get("7474/tcp", [])), "HTTP port 7474 is not exposed."
    assert any(x.get("HostPort") == "7687" for x in bindings.get("7687/tcp", [])), "Bolt port 7687 is not exposed."


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


def test_script_uses_parameters():
    with open(SCRIPT, "r") as f:
        content = f.read()
    assert "parameters" in content.lower() or "props" in content.lower() or "$1" in content, \
        "Script does not seem to use a parameterized query (missing 'parameters' in payload)."


def test_script_execution_and_output():
    install_curl_wrapper()
    neo4j_request("RETURN 1", retries=30)

    # Preserve the original assertion against the graph supplied by graph_setup.cypher.
    run_script_and_check("P1", ["P2", "P3", "P4", "P5", "P6", "P8"])

    # Add an unpredictable graph after the agent has finished. This checks direct,
    # indirect, duplicate-path, unrelated, and over-three-hop behavior.
    token = uuid.uuid4().hex
    ids = {name: f"VT_{token}_{name}" for name in ["ROOT", "A", "B", "C", "D", "E", "F", "OTHER"]}
    statement = """
    UNWIND $ids AS pid
    MERGE (:Paper {id: pid})
    WITH $m AS m
    MATCH (r:Paper {id:m.ROOT}), (a:Paper {id:m.A}), (b:Paper {id:m.B}),
          (c:Paper {id:m.C}), (d:Paper {id:m.D}), (e:Paper {id:m.E}),
          (f:Paper {id:m.F})
    MERGE (r)-[:CITES]->(a)
    MERGE (r)-[:CITES]->(b)
    MERGE (a)-[:CITES]->(c)
    MERGE (b)-[:CITES]->(c)
    MERGE (b)-[:CITES]->(f)
    MERGE (c)-[:CITES]->(d)
    MERGE (d)-[:CITES]->(e)
    """
    neo4j_request(statement, {"ids": list(ids.values()), "m": ids})
    expected = sorted([ids["A"], ids["B"], ids["C"], ids["D"], ids["F"]])
    run_script_and_check(ids["ROOT"], expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
