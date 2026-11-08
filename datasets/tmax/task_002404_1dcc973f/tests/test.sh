#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import subprocess
import tempfile
import uuid

AUDITOR = "/home/user/auditor"
SOURCE = "/home/user/auditor.c"
RUNNER = "/home/user/query_runner.py"
GRAPH = "/home/user/system_graph.ttl"
QUERY = "/home/user/query.rq"
LOG = "/home/user/audit_violations.log"
VENV_PYTHON = "/home/user/venv/bin/python"

ORIGINAL_EXPECTED = [
    "VIOLATION: AppServer1 connects to InternalAPI_A connects to UserDB",
    "VIOLATION: WebFront connects to InternalAPI_D connects to FinancialDB",
]


def read_log():
    with open(LOG, "r") as f:
        return [line.strip() for line in f if line.strip()]


def run_auditor(path, expected, marker=None):
    for artifact in (LOG, QUERY):
        if os.path.exists(artifact):
            os.remove(artifact)
    if marker and os.path.exists(marker):
        os.remove(marker)

    result = subprocess.run(
        [path], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, (
        f"{path} failed with exit code {result.returncode}\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.exists(QUERY), "The auditor did not create /home/user/query.rq."
    assert os.path.getsize(QUERY) > 0, "/home/user/query.rq is empty."
    assert os.path.exists(LOG), "The auditor did not create /home/user/audit_violations.log."
    assert read_log() == expected, f"Expected {expected}, found {read_log()}"
    if marker:
        assert os.path.exists(marker), "The auditor did not invoke /home/user/query_runner.py."


def test_audit_violations_log_exists():
    assert os.path.exists(LOG), "The file /home/user/audit_violations.log is missing."


def test_audit_violations_log_contents():
    assert read_log() == ORIGINAL_EXPECTED, (
        f"Contents of {LOG} do not match expected output.\n"
        f"Expected: {ORIGINAL_EXPECTED}\nFound: {read_log()}"
    )


def test_c_program_exists():
    assert os.path.exists(SOURCE), f"{SOURCE} is missing."
    assert os.path.exists(AUDITOR), f"{AUDITOR} is missing."
    assert os.access(AUDITOR, os.X_OK), f"{AUDITOR} is not executable."
    with open(AUDITOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{AUDITOR} is not a compiled ELF executable."


def test_python_script_exists():
    assert os.path.exists(RUNNER), f"{RUNNER} is missing."


def test_system_graph_exists():
    assert os.path.exists(GRAPH), f"{GRAPH} is missing."


def test_pipeline_is_functional_and_general():
    assert os.path.isfile(VENV_PYTHON) and os.access(VENV_PYTHON, os.X_OK), (
        "The virtual environment Python executable is missing."
    )
    env_check = subprocess.run(
        [VENV_PYTHON, "-c", "import rdflib,sys; assert sys.prefix == '/home/user/venv'"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert env_check.returncode == 0, f"rdflib is not installed in the virtual environment: {env_check.stderr}"

    # The submitted Python runner must independently execute arbitrary SPARQL.
    token = uuid.uuid4().hex
    runner_graph = f"/tmp/runner_graph_{token}.ttl"
    runner_query = f"/tmp/runner_query_{token}.rq"
    with open(runner_graph, "w") as f:
        f.write(
            "@prefix x: <http://example.org/test#> .\n"
            f"x:Source{token} x:links x:Target{token} .\n"
        )
    with open(runner_query, "w") as f:
        f.write(
            "PREFIX x: <http://example.org/test#>\n"
            "SELECT ?s ?o WHERE { ?s x:links ?o . }\n"
        )
    runner_result = subprocess.run(
        [VENV_PYTHON, RUNNER, runner_query, runner_graph],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert runner_result.returncode == 0, f"query_runner.py failed: {runner_result.stderr}"
    assert [line.strip() for line in runner_result.stdout.splitlines() if line.strip()] == [
        f"Source{token} Target{token}"
    ], "query_runner.py did not emit the requested raw node names as space-separated values."

    # Recompile the submitted C source so a dummy source file cannot accompany an unrelated artifact.
    rebuilt = f"/tmp/auditor_rebuilt_{token}"
    compile_result = subprocess.run(
        ["gcc", SOURCE, "-o", rebuilt], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compile_result.returncode == 0, f"auditor.c does not compile: {compile_result.stderr}"

    with open(SOURCE, "r", errors="replace") as f:
        source_text = f.read()
    assert re.search(r"\b(popen|system|fork|exec[a-z]*|posix_spawn)\b", source_text), (
        "auditor.c does not contain a standard process-chaining mechanism."
    )

    graph_backup = f"/tmp/system_graph_backup_{token}.ttl"
    runner_backup = f"/tmp/query_runner_backup_{token}.py"
    marker = f"/tmp/query_runner_called_{token}"
    shutil.copy2(GRAPH, graph_backup)
    shutil.copy2(RUNNER, runner_backup)

    # Random local names prevent a fixed output from satisfying this test. The Z
    # violation is deliberately listed first so the required alphabetical sort is exercised.
    a_public = f"APublic{token}"
    a_api = f"AApi{token}"
    a_db = f"ADb{token}"
    z_public = f"ZPublic{token}"
    z_api = f"ZApi{token}"
    z_db = f"ZDb{token}"
    alternate_ttl = f'''@prefix sys: <http://example.org/sys#> .

sys:{z_public} a sys:PublicFacing ; sys:connectsTo sys:{z_api} .
sys:{z_api} a sys:API ; sys:hasEncryption "false" ; sys:connectsTo sys:{z_db} .
sys:{z_db} a sys:PIIDatabase .

sys:{a_public} a sys:PublicFacing ; sys:connectsTo sys:{a_api} .
sys:{a_api} a sys:API ; sys:hasEncryption "false" ; sys:connectsTo sys:{a_db} .
sys:{a_db} a sys:PIIDatabase .

sys:EncryptedPublic{token} a sys:PublicFacing ; sys:connectsTo sys:EncryptedApi{token} .
sys:EncryptedApi{token} a sys:API ; sys:hasEncryption "true" ; sys:connectsTo sys:EncryptedDb{token} .
sys:EncryptedDb{token} a sys:PIIDatabase .

sys:InternalOnly{token} a sys:InternalSystem ; sys:connectsTo sys:InternalApi{token} .
sys:InternalApi{token} a sys:API ; sys:hasEncryption "false" ; sys:connectsTo sys:InternalDb{token} .
sys:InternalDb{token} a sys:PIIDatabase .
'''
    alternate_expected = [
        f"VIOLATION: {a_public} connects to {a_api} connects to {a_db}",
        f"VIOLATION: {z_public} connects to {z_api} connects to {z_db}",
    ]

    try:
        with open(GRAPH, "w") as f:
            f.write(alternate_ttl)

        # Wrap the real runner with a marker to prove that the C pipeline invokes it.
        with open(RUNNER, "w") as f:
            f.write(
                "import os, sys\n"
                f"open({marker!r}, 'w').close()\n"
                f"os.execv({VENV_PYTHON!r}, [{VENV_PYTHON!r}, {runner_backup!r}] + sys.argv[1:])\n"
            )

        run_auditor(AUDITOR, alternate_expected, marker)
        run_auditor(rebuilt, alternate_expected, marker)

        # Independently execute the generated query with rdflib and verify its tuple order and semantics.
        checker = f"/tmp/check_generated_query_{token}.py"
        with open(checker, "w") as f:
            f.write(
                "import json, sys\n"
                "from rdflib import Graph\n"
                "g = Graph(); g.parse(sys.argv[2], format='turtle')\n"
                "q = open(sys.argv[1]).read()\n"
                "def name(v):\n"
                "    s = str(v)\n"
                "    return s.rsplit('#', 1)[-1].rsplit('/', 1)[-1]\n"
                "print(json.dumps(sorted([[name(v) for v in row] for row in g.query(q)])))\n"
            )
        query_result = subprocess.run(
            [VENV_PYTHON, checker, QUERY, GRAPH], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert query_result.returncode == 0, f"Generated SPARQL query is invalid: {query_result.stderr}"
        assert json.loads(query_result.stdout) == sorted([
            [a_public, a_api, a_db],
            [z_public, z_api, z_db],
        ]), "Generated SPARQL did not select public node, API, and database in the required order."
    finally:
        shutil.copy2(graph_backup, GRAPH)
        shutil.copy2(runner_backup, RUNNER)

    # Execute the delivered binary again on the required graph and leave the required final log.
    run_auditor(AUDITOR, ORIGINAL_EXPECTED)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
