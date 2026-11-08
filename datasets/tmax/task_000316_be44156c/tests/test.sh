#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import stat
import subprocess
import tempfile

SCRIPT_PATH = '/home/user/auto_migrate.py'
LEGACY_PATH = '/home/user/legacy_deploy.py'
LOG_FILE = '/home/user/migration_log.json'


def test_auto_migrate_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a file."

    st = os.stat(SCRIPT_PATH)
    assert st.st_mode & stat.S_IXUSR, f"The script {SCRIPT_PATH} is not executable by the user."


def test_auto_migrate_uses_pexpect():
    with open(SCRIPT_PATH, 'r') as f:
        source = f.read()

    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        assert False, f"The automation script is not valid Python: {exc}"

    module_aliases = set()
    api_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'pexpect':
                    module_aliases.add(alias.asname or 'pexpect')
        elif isinstance(node, ast.ImportFrom) and node.module == 'pexpect':
            for alias in node.names:
                if alias.name in ('spawn', 'run'):
                    api_aliases.add(alias.asname or alias.name)

    uses_pexpect_api = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Attribute):
            if (isinstance(node.func.value, ast.Name)
                    and node.func.value.id in module_aliases
                    and node.func.attr in ('spawn', 'run')):
                uses_pexpect_api = True
        elif isinstance(node.func, ast.Name) and node.func.id in api_aliases:
            uses_pexpect_api = True

    assert module_aliases or api_aliases, "The automation script does not import pexpect."
    assert uses_pexpect_api, "The automation script does not use pexpect.spawn or pexpect.run."


def test_script_really_drives_legacy_tool_in_order():
    fd, transcript_path = tempfile.mkstemp(prefix='migration_transcript_', suffix='.jsonl')
    os.close(fd)

    instrumented_legacy = f'''#!/usr/bin/env python3
import json
import os
import sys

LOG_FILE = {LOG_FILE!r}
TRANSCRIPT_FILE = {transcript_path!r}

try:
    service_name = input("Enter service name to migrate: ").strip()
    version = input("Enter target version: ").strip()
    pre_checks = input("Verify pre-checks passed? (yes/no): ").strip()
    if pre_checks != "yes":
        print("Pre-checks failed. Aborting.")
        sys.exit(1)
    bring_online = input("Bring service online? (y/n): ").strip()
except EOFError:
    print("\\nUnexpected EOF. Migration aborted.")
    sys.exit(1)

with open(TRANSCRIPT_FILE, "a") as f:
    f.write(json.dumps([service_name, version, pre_checks, bring_online]) + "\\n")

status = "online" if bring_online == "y" else "offline"
try:
    with open(LOG_FILE, "r") as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {{}}
data[service_name] = {{"version": version, "status": status}}
with open(LOG_FILE, "w") as f:
    json.dump(data, f, indent=4)
print(f"Successfully migrated {{service_name}} to {{version}} ({{status}}).")
'''

    with open(LEGACY_PATH, 'rb') as f:
        original_legacy = f.read()
    original_mode = stat.S_IMODE(os.stat(LEGACY_PATH).st_mode)

    try:
        with open(LEGACY_PATH, 'w') as f:
            f.write(instrumented_legacy)
        os.chmod(LEGACY_PATH, 0o755)
        if os.path.exists(LOG_FILE):
            os.remove(LOG_FILE)

        result = subprocess.run(
            [SCRIPT_PATH],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    finally:
        with open(LEGACY_PATH, 'wb') as f:
            f.write(original_legacy)
        os.chmod(LEGACY_PATH, original_mode)

    assert result.returncode == 0, (
        f"The automation script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    with open(transcript_path, 'r') as f:
        interactions = [json.loads(line) for line in f if line.strip()]
    os.remove(transcript_path)

    assert interactions == [
        ['worker-1', 'v2.1', 'yes', 'y'],
        ['worker-2', 'v2.1', 'yes', 'y'],
        ['worker-3', 'v2.1', 'yes', 'y'],
    ], f"Expected three ordered legacy-tool interactions, got: {interactions!r}"


def test_migration_log_contains_expected_state():
    assert os.path.exists(LOG_FILE), f"The migration log file {LOG_FILE} does not exist. Did the script run successfully?"
    assert os.path.isfile(LOG_FILE), f"The path {LOG_FILE} is not a file."

    with open(LOG_FILE, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {LOG_FILE} does not contain valid JSON."

    expected_services = ['worker-1', 'worker-2', 'worker-3']

    for srv in expected_services:
        assert srv in data, f"Missing '{srv}' in {LOG_FILE}."

        srv_data = data[srv]
        assert 'version' in srv_data, f"Missing 'version' for '{srv}' in {LOG_FILE}."
        assert srv_data['version'] == 'v2.1', f"Expected version 'v2.1' for '{srv}', but got '{srv_data['version']}'."

        assert 'status' in srv_data, f"Missing 'status' for '{srv}' in {LOG_FILE}."
        assert srv_data['status'] == 'online', f"Expected status 'online' for '{srv}', but got '{srv_data['status']}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
