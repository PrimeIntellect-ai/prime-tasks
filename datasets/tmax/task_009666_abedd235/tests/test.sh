#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import re
import secrets
import shutil
import subprocess

import pytest

SCRIPT_PATH = "/home/user/optimized_query.sh"
RESULTS_PATH = "/home/user/results.json"
INFRA_PATH = "/home/user/infra.ttl"

EXPECTED_INFRA = '''@prefix ex: <http://example.org/> .

ex:Server1 ex:runs ex:SoftwareA .
ex:Server2 ex:runs ex:SoftwareB .
ex:Server3 ex:runs ex:SoftwareA .

ex:Alice ex:accesses ex:Server1 .
ex:Bob ex:accesses ex:Server2 .
ex:Charlie ex:accesses ex:Server3 .
ex:David ex:accesses ex:Server1 .

ex:SoftwareA ex:hasVulnerability "CVE-2023-1234" .
ex:SoftwareB ex:hasVulnerability "CVE-2023-9999" .

ex:Alice ex:name "Alice" .
ex:Bob ex:name "Bob" .
ex:Charlie ex:name "Charlie" .
ex:David ex:name "David" .
'''


def load_json_output(text, source):
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pytest.fail(f"{source} does not contain valid JSON.")


def test_roqet_installed():
    """Check if rasqal-utils (roqet) is installed."""
    assert shutil.which("roqet") is not None, "The 'roqet' command is not installed. Did you install 'rasqal-utils'?"
    package = subprocess.run(
        ["dpkg-query", "-W", "-f=${Status}", "rasqal-utils"],
        capture_output=True,
        text=True,
    )
    assert package.returncode == 0 and package.stdout.strip() == "install ok installed", \
        "The rasqal-utils package is not installed."


def test_optimized_query_script():
    """Check if optimized_query.sh exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_infra_was_not_modified():
    with open(INFRA_PATH, "r") as f:
        assert f.read() == EXPECTED_INFRA, "The original infra.ttl file was modified."


def test_results_json():
    """Check if results.json contains the correct SPARQL JSON output."""
    assert os.path.isfile(RESULTS_PATH), f"Results file {RESULTS_PATH} does not exist."

    try:
        with open(RESULTS_PATH, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {RESULTS_PATH} does not contain valid JSON.")

    assert "results" in data and "bindings" in data["results"], "JSON does not match SPARQL Query Results JSON Format."

    bindings = data["results"]["bindings"]
    assert len(bindings) == 2, f"Expected exactly 2 results due to LIMIT 2, but got {len(bindings)}."

    expected_names = ["Alice", "Charlie"]

    for i, expected_name in enumerate(expected_names):
        binding = bindings[i]
        assert "employeeName" in binding, f"Result {i+1} is missing the 'employeeName' variable."
        assert "server" in binding, f"Result {i+1} is missing the 'server' variable."

        actual_name = binding["employeeName"]["value"]
        assert actual_name == expected_name, f"Expected employeeName '{expected_name}' at position {i+1}, but got '{actual_name}'."

        actual_server = binding["server"]["value"]
        if expected_name == "Alice":
            assert "Server1" in actual_server, f"Alice should be associated with Server1, got {actual_server}"
        elif expected_name == "Charlie":
            assert "Server3" in actual_server, f"Charlie should be associated with Server3, got {actual_server}"


def test_script_dynamic_parameter():
    """Test if optimized_query.sh dynamically accepts the vulnerability ID parameter."""
    result = subprocess.run(
        [SCRIPT_PATH, "CVE-2023-9999"],
        capture_output=True,
        text=True
    )

    assert result.returncode == 0, f"Running {SCRIPT_PATH} failed with error:\n{result.stderr}"
    data = load_json_output(result.stdout, f"Output of {SCRIPT_PATH}")
    bindings = data.get("results", {}).get("bindings", [])

    assert len(bindings) == 1, f"Expected exactly 1 result for CVE-2023-9999, but got {len(bindings)}."
    assert bindings[0]["employeeName"]["value"] == "Bob", "Expected employeeName 'Bob' for CVE-2023-9999."
    assert "Server2" in bindings[0]["server"]["value"], "Expected Server2 for CVE-2023-9999."


def test_script_uses_roqet_with_a_real_dynamic_joined_query():
    """Exercise an unpredictable graph and verify that roqet executes the query producing the answer."""
    token = secrets.token_hex(8)
    vuln = f"CVE-RANDOM-{token}"
    names = [f"Bravo_{token}", f"Delta_{token}", f"Mike_{token}", f"Zulu_{token}"]
    servers = [f"TargetServer{i}_{token}" for i in range(4)]
    employees = [f"Employee{i}_{token}" for i in range(4)]
    decoy_name = f"AlphaDecoy_{token}"

    lines = ["@prefix ex: <http://example.org/> .", ""]
    for server in servers:
        lines.append(f"ex:{server} ex:runs ex:TargetSoftware_{token} .")
    lines += [
        f'ex:TargetSoftware_{token} ex:hasVulnerability "{vuln}" .',
        f"ex:SafeServer_{token} ex:runs ex:SafeSoftware_{token} .",
        f'ex:SafeSoftware_{token} ex:hasVulnerability "SAFE-{token}" .',
        "",
    ]
    for employee, name, server in zip(employees, names, servers):
        lines.append(f"ex:{employee} ex:name \"{name}\" .")
        lines.append(f"ex:{employee} ex:accesses ex:{server} .")
    lines += [
        f'ex:Decoy_{token} ex:name "{decoy_name}" .',
        f"ex:Decoy_{token} ex:accesses ex:SafeServer_{token} .",
        "",
    ]
    randomized_graph = "\n".join(lines)

    roqet_path = shutil.which("roqet")
    assert roqet_path is not None
    roqet_path = os.path.realpath(roqet_path)
    real_roqet = roqet_path + ".verifier-real"
    log_path = "/tmp/roqet-verifier-log.jsonl"

    with open(INFRA_PATH, "rb") as f:
        original_graph = f.read()

    if os.path.exists(log_path):
        os.unlink(log_path)
    assert not os.path.exists(real_roqet), f"Unexpected verifier backup path already exists: {real_roqet}"

    os.rename(roqet_path, real_roqet)
    wrapper = f'''#!/usr/bin/python3
import base64, json, os, subprocess, sys
args = sys.argv[1:]
files = {{}}
for arg in args:
    if os.path.isfile(arg):
        try:
            with open(arg, "r") as f:
                files[arg] = f.read()
        except Exception:
            pass
p = subprocess.run([{real_roqet!r}] + args, capture_output=True)
entry = {{"args": args, "files": files, "stdout": base64.b64encode(p.stdout).decode("ascii")}}
with open({log_path!r}, "a") as f:
    f.write(json.dumps(entry) + "\\n")
sys.stdout.buffer.write(p.stdout)
sys.stderr.buffer.write(p.stderr)
sys.exit(p.returncode)
'''

    try:
        with open(roqet_path, "w") as f:
            f.write(wrapper)
        os.chmod(roqet_path, 0o755)
        with open(INFRA_PATH, "w") as f:
            f.write(randomized_graph)

        result = subprocess.run([SCRIPT_PATH, vuln], capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, f"Randomized execution failed:\n{result.stderr}"
        data = load_json_output(result.stdout, "Randomized script output")

        assert set(data.get("head", {}).get("vars", [])) == {"employeeName", "server"}, \
            "The SPARQL result must select exactly employeeName and server."
        bindings = data.get("results", {}).get("bindings", [])
        assert len(bindings) == 2, "The query must apply LIMIT 2 when more than two matches exist."
        assert [b["employeeName"]["value"] for b in bindings] == names[:2], \
            "Results were not sorted by employeeName ascending or included an employee without access."
        assert [b["server"]["value"] for b in bindings] == [
            f"http://example.org/{servers[0]}",
            f"http://example.org/{servers[1]}",
        ], "Employees were not joined to the servers they actually access."
        assert all(set(b) == {"employeeName", "server"} for b in bindings), \
            "Each result must contain only the two selected variables."

        assert os.path.isfile(log_path), "optimized_query.sh did not invoke the installed roqet command."
        with open(log_path, "r") as f:
            calls = [json.loads(line) for line in f if line.strip()]

        matching_calls = []
        for call in calls:
            args = call["args"]
            material = "\n".join(args) + "\n" + "\n".join(call.get("files", {}).values())
            has_json_flag = any(args[i] == "-r" and i + 1 < len(args) and args[i + 1] == "json" for i in range(len(args)))
            if vuln in material and has_json_flag:
                matching_calls.append(call)

        assert matching_calls, "roqet was not invoked with -r json and a query parameterized by the supplied vulnerability ID."
        assert any(load_json_output(base64.b64decode(c["stdout"]).decode(), "Captured roqet output") == data
                   for c in matching_calls), \
            "The script output was not the result produced by roqet for the dynamic query."

        with open(SCRIPT_PATH, "r") as f:
            script_text = f.read()
        assert re.search(r"\$\{?1(?:\}|\b)", script_text), "The script must use the first Bash positional parameter."
        assert re.search(r"\bORDER\s+BY\b", script_text, re.I), "The SPARQL query is missing ORDER BY."
        assert re.search(r"\bLIMIT\s+2\b", script_text, re.I), "The SPARQL query is missing LIMIT 2."
    finally:
        with open(INFRA_PATH, "wb") as f:
            f.write(original_graph)
        if os.path.exists(roqet_path):
            os.unlink(roqet_path)
        if os.path.exists(real_roqet):
            os.rename(real_roqet, roqet_path)


def test_saved_results_are_exact_script_output():
    run = subprocess.run([SCRIPT_PATH, "CVE-2023-1234"], capture_output=True, timeout=20)
    assert run.returncode == 0, f"Running {SCRIPT_PATH} for the saved result failed."
    with open(RESULTS_PATH, "rb") as f:
        saved = f.read()
    assert saved == run.stdout, "results.json is not the exact output of optimized_query.sh for CVE-2023-1234."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
