#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import subprocess
import sys
import tempfile

import pytest


def test_graph_store_behavior():
    sys.path.insert(0, "/app")
    from graph_backup_store import GraphStore

    data_file = "/home/user/backups.json"
    with open(data_file, "r") as f:
        backups = json.load(f)

    store = GraphStore(data_file)
    for node in backups:
        assert store.get_parent(node["id"]) == node.get("parent_id"), \
            f"Incorrect parent lookup for {node['id']}"

    assert store.get_parent("__missing_backup__") is None

    fixture = [
        {"id": "root"},
        {"id": "child", "parent_id": "root"},
        {"id": 1},
        {"id": 2, "parent_id": 1},
    ]
    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        json.dump(fixture, f)
        fixture_path = f.name

    try:
        fixture_store = GraphStore(fixture_path)
        assert fixture_store.get_parent("root") is None
        assert fixture_store.get_parent("child") == "root"
        assert fixture_store.get_parent(1) is None
        assert fixture_store.get_parent(2) == 1
    finally:
        os.unlink(fixture_path)


def test_get_lineage_fuzz_equivalence():
    agent_script = "/home/user/get_lineage.py"
    oracle_script = "/tests/oracle_get_lineage.py"
    data_file = "/home/user/backups.json"

    assert os.path.isfile(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing: {oracle_script}"
    assert os.path.isfile(data_file), f"Data file missing: {data_file}"

    with open(data_file, "r") as f:
        backups = json.load(f)

    if isinstance(backups, list):
        backup_ids = [b["id"] for b in backups]
        parent_index = {b["id"]: b.get("parent_id") for b in backups}
    elif isinstance(backups, dict):
        backup_ids = list(backups.keys())
        parent_index = {
            key: value.get("parent_id") if isinstance(value, dict) else None
            for key, value in backups.items()
        }
    else:
        pytest.fail("Unexpected format for backups.json")

    assert len(backup_ids) > 0, "No backups found in backups.json"

    hook_dir = "/tmp/lineage_hook"
    os.makedirs(hook_dir, exist_ok=True)
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w") as f:
        f.write(r'''
import json
import os

try:
    from graph_backup_store import GraphStore

    _original_init = GraphStore.__init__
    _original_get_parent = GraphStore.get_parent

    def _record(event):
        path = os.environ.get("GRAPH_STORE_USAGE_LOG")
        if path:
            with open(path, "a") as log:
                log.write(json.dumps(event) + "\\n")

    def _tracked_init(self, data_path, *args, **kwargs):
        result = _original_init(self, data_path, *args, **kwargs)
        _record(["INIT", os.path.realpath(str(data_path))])
        return result

    def _tracked_get_parent(self, node_id, *args, **kwargs):
        result = _original_get_parent(self, node_id, *args, **kwargs)
        _record(["GET", node_id, result])
        return result

    GraphStore.__init__ = _tracked_init
    GraphStore.get_parent = _tracked_get_parent
except Exception:
    pass
''')

    random.seed(42)
    fuzz_inputs = random.sample(backup_ids, min(100, len(backup_ids)))

    for index, backup_id in enumerate(fuzz_inputs):
        oracle_cmd = ["python3", oracle_script, str(backup_id)]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, \
            f"Oracle failed on input {backup_id}:\n{oracle_res.stderr}"
        oracle_output = oracle_res.stdout.strip()

        usage_log = f"/tmp/graph_store_usage_{index}.jsonl"
        if os.path.exists(usage_log):
            os.unlink(usage_log)

        env = os.environ.copy()
        env["GRAPH_STORE_USAGE_LOG"] = usage_log
        env["PYTHONPATH"] = hook_dir + os.pathsep + "/app" + (
            os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else ""
        )

        agent_cmd = ["python3", agent_script, str(backup_id)]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True, env=env)

        if agent_res.returncode != 0:
            pytest.fail(
                f"Agent script failed on input {backup_id}.\n"
                f"Stderr: {agent_res.stderr}\nStdout: {agent_res.stdout}"
            )

        agent_output = agent_res.stdout.strip()
        assert agent_output == oracle_output, (
            f"Mismatch on input '{backup_id}'.\n"
            f"Expected (Oracle): {oracle_output}\n"
            f"Actual (Agent)  : {agent_output}"
        )

        assert os.path.isfile(usage_log), \
            "The lineage script did not use graph_backup_store.GraphStore"
        with open(usage_log, "r") as f:
            events = [json.loads(line) for line in f if line.strip()]

        assert ["INIT", os.path.realpath(data_file)] in events, \
            "The lineage script did not initialize GraphStore with backups.json"

        expected_gets = []
        current = backup_id
        while current is not None:
            parent = parent_index.get(current)
            expected_gets.append(["GET", current, parent])
            current = parent

        actual_gets = [event for event in events if event and event[0] == "GET"]
        assert actual_gets == expected_gets, \
            "The lineage script must query each lineage edge through GraphStore.get_parent"


def test_bug_fixed_in_store():
    store_path = "/app/graph_backup_store/store.py"
    assert os.path.isfile(store_path), f"File {store_path} is missing."

    with open(store_path, "r") as f:
        content = f.read()

    assert "node.get('parent_id', node['id'])" not in content and \
           'node.get("parent_id", node["id"])' not in content, \
        "The infinite loop bug in /app/graph_backup_store/store.py was not fixed."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
