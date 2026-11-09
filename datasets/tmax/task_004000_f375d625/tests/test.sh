#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import sqlite3
import stat
import subprocess
import uuid
from collections import deque


def _constant_string(node, assignments):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name):
        return assignments.get(node.id)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left = _constant_string(node.left, assignments)
        right = _constant_string(node.right, assignments)
        if left is not None and right is not None:
            return left + right
    if isinstance(node, ast.JoinedStr):
        parts = []
        for value in node.values:
            if not isinstance(value, ast.Constant) or not isinstance(value.value, str):
                return None
            parts.append(value.value)
        return "".join(parts)
    return None


def _check_implementation(script_path):
    assert os.path.isfile(script_path), f"Agent script missing at {script_path}"
    assert not os.path.islink(script_path), "Agent script must be a real Python source file"

    with open(script_path, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=script_path)

    sqlite_module_aliases = set()
    sqlite_connect_aliases = set()
    forbidden_modules = {"subprocess", "ctypes"}

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                root = alias.name.split(".")[0]
                assert root not in forbidden_modules, "The replacement may not invoke or load an external binary"
                if alias.name == "sqlite3":
                    sqlite_module_aliases.add(alias.asname or "sqlite3")
        elif isinstance(node, ast.ImportFrom):
            root = (node.module or "").split(".")[0]
            assert root not in forbidden_modules, "The replacement may not invoke or load an external binary"
            if node.module == "sqlite3":
                for alias in node.names:
                    if alias.name == "connect":
                        sqlite_connect_aliases.add(alias.asname or alias.name)

    assert sqlite_module_aliases or sqlite_connect_aliases, "Script must import Python's sqlite3 module"

    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = _constant_string(node.value, assignments) if node.value is not None else None
            if value is not None:
                targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                for target in targets:
                    if isinstance(target, ast.Name):
                        assignments[target.id] = value

    saw_connect = False
    saw_parameterized_recursive_execute = False
    forbidden_os_calls = {
        "system", "popen", "fork", "forkpty", "posix_spawn", "posix_spawnp",
        "spawnl", "spawnle", "spawnlp", "spawnlpe", "spawnv", "spawnve",
        "spawnvp", "spawnvpe", "execl", "execle", "execlp", "execlpe",
        "execv", "execve", "execvp", "execvpe",
    }

    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            assert "legacy_lineage" not in node.value, "Script must not delegate to the legacy executable"

        if not isinstance(node, ast.Call):
            continue

        if isinstance(node.func, ast.Name):
            assert node.func.id not in {"exec", "eval", "compile", "__import__"}, \
                "Dynamic code loading is not permitted for this replacement"
            if node.func.id in sqlite_connect_aliases:
                saw_connect = True
        elif isinstance(node.func, ast.Attribute):
            if isinstance(node.func.value, ast.Name):
                if node.func.value.id in sqlite_module_aliases and node.func.attr == "connect":
                    saw_connect = True
                if node.func.value.id == "os" and node.func.attr in forbidden_os_calls:
                    raise AssertionError("The replacement may not invoke an external executable")

            if node.func.attr == "execute" and len(node.args) >= 2:
                query = _constant_string(node.args[0], assignments)
                if query is not None:
                    normalized = " ".join(query.lower().split())
                    if ("with recursive" in normalized and "datasets" in normalized
                            and "transformations" in normalized and "join" in normalized
                            and "?" in query):
                        saw_parameterized_recursive_execute = True

    assert saw_connect, "Script must open the supplied database with sqlite3.connect"
    assert saw_parameterized_recursive_execute, \
        "Script must execute a parameterized recursive CTE joining datasets and transformations"


def _run_agent(script, db_path, dataset_id):
    return subprocess.run(
        ["python3", script, db_path, str(dataset_id)],
        capture_output=True,
        text=True,
        timeout=15,
    )


def _create_hidden_database(path):
    rng = random.SystemRandom()
    ids = sorted(rng.sample(range(10000, 90000), 45))
    names = {dataset_id: f"hidden_dataset_{rng.randrange(10**12)}" for dataset_id in ids}

    edges = set()
    for index in range(1, len(ids)):
        edges.add((ids[rng.randrange(index)], ids[index]))
    while len(edges) < 65:
        a = rng.randrange(0, len(ids) - 1)
        b = rng.randrange(a + 1, len(ids))
        edges.add((ids[a], ids[b]))

    conn = sqlite3.connect(path)
    try:
        conn.execute("CREATE TABLE datasets(id INTEGER PRIMARY KEY, name TEXT)")
        conn.execute("CREATE TABLE transformations(id INTEGER PRIMARY KEY, source_id INTEGER, target_id INTEGER, operation TEXT)")
        conn.executemany("INSERT INTO datasets(id, name) VALUES (?, ?)", names.items())
        conn.executemany(
            "INSERT INTO transformations(id, source_id, target_id, operation) VALUES (?, ?, ?, ?)",
            [(i, src, tgt, "hidden_transform") for i, (src, tgt) in enumerate(sorted(edges), 1)],
        )
        conn.commit()
    finally:
        conn.close()
    return ids, names, edges


def _expected_lineage(target, names, edges):
    incoming = {}
    for source, target_id in edges:
        incoming.setdefault(target_id, []).append(source)

    distances = {target: 0}
    queue = deque([target])
    while queue:
        current = queue.popleft()
        for source in incoming.get(current, []):
            candidate = distances[current] + 1
            if source not in distances or candidate < distances[source]:
                distances[source] = candidate
                queue.append(source)

    return [
        {"id": dataset_id, "name": names[dataset_id], "distance": distance}
        for dataset_id, distance in sorted(distances.items(), key=lambda item: (item[1], item[0]))
    ]


def test_fast_lineage_complete_verification():
    db_path = "/home/user/data_lineage.db"
    agent_script = "/home/user/fast_lineage.py"
    oracle_binary = "/app/legacy_lineage"

    assert os.path.exists(agent_script), f"Agent script missing at {agent_script}"
    assert os.path.exists(oracle_binary), f"Oracle binary missing at {oracle_binary}"
    assert os.path.exists(db_path), f"Database missing at {db_path}"

    _check_implementation(agent_script)

    # Preserve the original fuzz-equivalence assertions.
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT id FROM datasets;")
    all_ids = [row[0] for row in cursor.fetchall()]
    conn.close()
    assert len(all_ids) > 0, "No datasets found in the database."

    random.seed(42)
    fuzz_inputs = random.sample(all_ids, min(50, len(all_ids)))
    for dataset_id in fuzz_inputs:
        oracle_result = subprocess.run(
            [oracle_binary, db_path, str(dataset_id)], capture_output=True, text=True, timeout=15
        )
        assert oracle_result.returncode == 0, f"Oracle failed on input {dataset_id}:\n{oracle_result.stderr}"
        agent_result = _run_agent(agent_script, db_path, dataset_id)
        assert agent_result.returncode == 0, f"Agent script failed on input {dataset_id}:\n{agent_result.stderr}"
        try:
            oracle_json = json.loads(oracle_result.stdout.strip())
            agent_json = json.loads(agent_result.stdout.strip())
            assert oracle_json == agent_json, f"Output mismatch for dataset {dataset_id}"
        except json.JSONDecodeError:
            assert oracle_result.stdout.strip() == agent_result.stdout.strip(), \
                f"Output mismatch for dataset {dataset_id}"

    # Exercise an unpredictable database and derive answers independently. Remove
    # the legacy executable while doing so, preventing direct delegation by path.
    hidden_db = f"/tmp/lineage_{uuid.uuid4().hex}.db"
    ids, names, edges = _create_hidden_database(hidden_db)
    with open(oracle_binary, "rb") as f:
        oracle_bytes = f.read()
    oracle_mode = stat.S_IMODE(os.stat(oracle_binary).st_mode)
    os.unlink(oracle_binary)
    try:
        rng = random.SystemRandom()
        targets = list(dict.fromkeys(ids[-12:] + rng.sample(ids, 12)))
        for target in targets:
            result = _run_agent(agent_script, hidden_db, target)
            assert result.returncode == 0, f"Agent failed on hidden dataset {target}:\n{result.stderr}"
            try:
                actual = json.loads(result.stdout)
            except json.JSONDecodeError as exc:
                raise AssertionError(f"Agent emitted invalid JSON for hidden dataset {target}: {exc}")
            assert actual == _expected_lineage(target, names, edges), \
                f"Incorrect lineage for hidden dataset {target}"
    finally:
        with open(oracle_binary, "wb") as f:
            f.write(oracle_bytes)
        os.chmod(oracle_binary, oracle_mode)
        if os.path.exists(hidden_db):
            os.unlink(hidden_db)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
