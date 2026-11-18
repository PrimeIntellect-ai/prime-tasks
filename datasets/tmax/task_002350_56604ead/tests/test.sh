#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/audit_sandbox_runner.py
import os
import pwd
import runpy
import sys

script = sys.argv[1]
user = pwd.getpwnam("user")

# Drop verifier root privileges before executing the submitted artifact.
os.initgroups(user.pw_name, user.pw_gid)
os.setgid(user.pw_gid)
os.setuid(user.pw_uid)

blocked_events = (
    "subprocess.",
    "socket.",
    "ctypes.",
    "os.system",
    "os.exec",
    "os.spawn",
    "os.posix_spawn",
    "os.fork",
    "os.forkpty",
)

def audit_hook(event, args):
    if event.startswith(blocked_events):
        raise PermissionError("external process and native-code access are disabled")
    if event == "open" and args and isinstance(args[0], str):
        path = os.path.abspath(args[0])
        if path == "/app/legacy_audit_tool":
            raise PermissionError("legacy oracle is unavailable during verification")

sys.addaudithook(audit_hook)
sys.argv = [script]
runpy.run_path(script, run_name="__main__")
RUNNER_EOF
chmod 755 /tmp/audit_sandbox_runner.py

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import io
import json
import os
import random
import shutil
import string
import subprocess
import sys
import tempfile
import uuid
from collections import defaultdict

import pytest

AGENT_SCRIPT = "/home/user/audit_processor.py"
ORACLE_BINARY = "/app/legacy_audit_tool"
RUNNER = "/tmp/audit_sandbox_runner.py"

DENIED_IMPORTS = {
    "asyncio", "builtins", "ctypes", "importlib", "multiprocessing",
    "os", "pty", "runpy", "socket", "subprocess",
}
DENIED_CALLS = {"__import__", "compile", "eval", "exec", "open"}
DENIED_ATTRIBUTES = {
    "CDLL", "PyDLL", "dlopen", "fork", "forkpty", "modules", "popen",
    "posix_spawn", "system",
}


def generate_random_string(min_len=5, max_len=10):
    length = random.randint(min_len, max_len)
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))


def generate_csv_input():
    num_lines = random.randint(50, 500)
    lines = ["EventID,Actor,Target,ActionType,SeverityScore"]
    action_types = ['READ', 'WRITE', 'DELETE', 'GRANT']
    actors_pool = [generate_random_string() for _ in range(random.randint(5, 20))]
    targets_pool = [generate_random_string() for _ in range(random.randint(5, 20))]

    for _ in range(num_lines):
        lines.append(','.join([
            str(uuid.uuid4()),
            random.choice(actors_pool),
            random.choice(targets_pool),
            random.choice(action_types),
            str(random.randint(1, 20)),
        ]))
    return "\n".join(lines) + "\n"


def expected_output(csv_data):
    lines = csv_data.splitlines()
    if not lines:
        return "[]"

    actor_risk = defaultdict(int)
    target_actors = defaultdict(set)
    for row in csv.DictReader(lines):
        try:
            score = int(row.get("SeverityScore", 0))
            if score < 5:
                continue
            actor = row["Actor"]
            target = row["Target"]
            actor_risk[actor] += score
            target_actors[target].add(actor)
        except Exception:
            continue

    vulnerability = {
        target: sum(actor_risk[actor] for actor in actors)
        for target, actors in target_actors.items()
    }
    top_ten = sorted(vulnerability.items(), key=lambda item: (-item[1], item[0]))[:10]
    result = [
        {"target": target, "vulnerability_index": score}
        for target, score in top_ten
    ]
    return json.dumps(result, separators=(",", ":"))


def assert_transparent_python_source():
    with open(AGENT_SCRIPT, "rb") as fh:
        source_bytes = fh.read()
    assert source_bytes, "Agent script is empty"
    assert not source_bytes.startswith(b"\x7fELF"), "Submission must be Python source"

    try:
        source = source_bytes.decode("utf-8")
        tree = ast.parse(source, filename=AGENT_SCRIPT)
    except (UnicodeDecodeError, SyntaxError) as exc:
        pytest.fail(f"Submission is not valid UTF-8 Python source: {exc}")

    lowered = source.lower()
    assert "legacy_audit_tool" not in lowered and "/app/" not in lowered, (
        "Submission may not reference the proprietary executable"
    )

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                assert alias.name.split('.')[0] not in DENIED_IMPORTS, (
                    f"Non-transparent import is not allowed: {alias.name}"
                )
        elif isinstance(node, ast.ImportFrom):
            root = (node.module or "").split('.')[0]
            assert root not in DENIED_IMPORTS, (
                f"Non-transparent import is not allowed: {node.module}"
            )
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Name):
            assert node.func.id not in DENIED_CALLS, (
                f"Dynamic execution/file access is not allowed: {node.func.id}"
            )
        elif isinstance(node, ast.Attribute):
            assert node.attr not in DENIED_ATTRIBUTES, (
                f"External execution access is not allowed: {node.attr}"
            )
            assert not node.attr.startswith("__"), "Dunder introspection is not allowed"
        elif isinstance(node, ast.Name):
            assert not node.id.startswith("__"), "Dunder introspection is not allowed"


def run_agent(csv_data, iteration):
    try:
        proc = subprocess.run(
            [sys.executable, RUNNER, AGENT_SCRIPT],
            input=csv_data,
            text=True,
            capture_output=True,
            check=True,
            timeout=5,
        )
    except subprocess.CalledProcessError as exc:
        pytest.fail(f"Agent script failed on iteration {iteration}. Stderr: {exc.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Agent script timed out on iteration {iteration}.")
    return proc.stdout.strip()


def test_audit_processor_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"
    assert_transparent_python_source()


def test_fuzz_equivalence():
    # Preserve the original environment assertion, but remove the executable from
    # the submitted program's namespace while behavioral checks are running.
    assert os.path.exists(ORACLE_BINARY), f"Oracle binary missing at {ORACLE_BINARY}"

    hidden_dir = tempfile.mkdtemp(prefix="audit-oracle-", dir="/root")
    os.chmod(hidden_dir, 0o700)
    hidden_oracle = os.path.join(hidden_dir, "legacy_audit_tool")
    os.replace(ORACLE_BINARY, hidden_oracle)

    try:
        random.seed(42)
        for i in range(100):
            csv_data = generate_csv_input()
            expected = expected_output(csv_data)
            actual = run_agent(csv_data, i)
            assert actual == expected, (
                f"Output mismatch on iteration {i}!\n\n"
                f"Input CSV:\n{csv_data}\n\n"
                f"Expected output:\n{expected}\n\n"
                f"Agent output:\n{actual}"
            )
    finally:
        if os.path.exists(hidden_oracle):
            os.replace(hidden_oracle, ORACLE_BINARY)
        shutil.rmtree(hidden_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
