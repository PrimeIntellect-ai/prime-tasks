#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import subprocess
import uuid
import pytest

OUTPUT = "/home/user/output.json"
EMPLOYEES = "/home/user/employees.json"
APP = "/home/user/app"


def find_mongo_shell():
    for path in [
        "/home/user/mongodb/bin/mongosh",
        "/home/user/mongodb/bin/mongo",
        "mongosh",
        "mongo",
    ]:
        try:
            result = subprocess.run([path, "--version"], capture_output=True, text=True)
            if result.returncode == 0:
                return path
        except FileNotFoundError:
            pass
    return None


def mongo_eval(javascript, check=True):
    shell = find_mongo_shell()
    assert shell is not None, "Could not find 'mongosh' or 'mongo' binary to verify database state."
    result = subprocess.run(
        [shell, "127.0.0.1:27017/company", "--quiet", "--eval", javascript],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if check:
        assert result.returncode == 0, f"MongoDB command failed: {result.stderr}"
    return result


def parse_shell_json(stdout):
    text = stdout.strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        for line in reversed(text.splitlines()):
            try:
                return json.loads(line.strip())
            except json.JSONDecodeError:
                continue
    raise AssertionError(f"Mongo shell did not return valid JSON: {stdout}")


def expected_subordinates(documents, manager_id, skip, limit):
    children = {}
    for document in documents:
        children.setdefault(document.get("managerId"), []).append(document)

    found = []
    stack = list(children.get(manager_id, []))
    seen = set()
    while stack:
        document = stack.pop()
        employee_id = document["_id"]
        if employee_id in seen:
            continue
        seen.add(employee_id)
        found.append(document)
        stack.extend(children.get(employee_id, []))

    found.sort(key=lambda document: document["_id"])
    return found[skip:skip + limit]


def read_output():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist."
    with open(OUTPUT, encoding="utf-8") as handle:
        try:
            return json.load(handle)
        except json.JSONDecodeError as exc:
            pytest.fail(f"{OUTPUT} is not valid JSON: {exc}")


def assert_two_space_indentation():
    with open(OUTPUT, encoding="utf-8") as handle:
        text = handle.read()
    data = json.loads(text)
    expected_text = json.dumps(data, indent=2, ensure_ascii=False)
    assert text.rstrip("\n") == expected_text, f"{OUTPUT} must be indented with 2 spaces."


def run_program(manager_id, skip, limit):
    command = [
        "runuser", "-u", "user", "--",
        "env", "HOME=/home/user", "GOCACHE=/home/user/.cache/go-build",
        "GOMODCACHE=/home/user/go/pkg/mod",
        "go", "run", "query.go", manager_id, str(skip), str(limit),
    ]
    result = subprocess.run(command, cwd=APP, capture_output=True, text=True, timeout=180)
    assert result.returncode == 0, (
        f"query.go failed for arguments {manager_id!r} {skip} {limit}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return read_output()


def replace_employees(documents):
    encoded = json.dumps(documents, separators=(",", ":"))
    mongo_eval(
        f"const docs={encoded}; db.employees.deleteMany({{}}); "
        "if (docs.length) db.employees.insertMany(docs);"
    )


def test_output_json_exists_and_correct():
    """Preserve the required final-state check and verify complete source documents."""
    with open(EMPLOYEES, encoding="utf-8") as handle:
        source = json.load(handle)

    data = read_output()
    assert isinstance(data, list), f"{OUTPUT} should contain a JSON array."
    assert len(data) == 3, f"Expected exactly 3 documents in {OUTPUT}, got {len(data)}."

    expected_ids = ["E5", "E7", "E8"]
    actual_ids = [doc.get("_id") for doc in data]
    assert actual_ids == expected_ids, (
        f"Expected documents with _ids {expected_ids} in order, but got {actual_ids}."
    )

    expected = expected_subordinates(source, "E2", 1, 3)
    assert data == expected, "output.json must contain the exact complete subordinate documents."
    assert_two_space_indentation()


def test_managerid_index_exists():
    """Preserve the index check and require the requested ascending key."""
    result = mongo_eval("JSON.stringify(db.employees.getIndexes())")
    try:
        indexes = parse_shell_json(result.stdout)
    except AssertionError:
        assert "managerId" in result.stdout, "Could not find index on managerId in the collection."
        return

    has_managerid_index = any("managerId" in index.get("key", {}) for index in indexes)
    assert has_managerid_index, "No index found on 'managerId' field in 'company.employees' collection."
    assert any(index.get("key", {}).get("managerId") == 1 for index in indexes), (
        "No ascending index found on 'managerId' in 'company.employees'."
    )


def test_go_program_executes_dynamic_graph_pipeline():
    query_path = os.path.join(APP, "query.go")
    module_path = os.path.join(APP, "go.mod")
    assert os.path.isfile(query_path), f"Required Go program {query_path} does not exist."
    assert os.path.isfile(module_path), f"Required Go module file {module_path} does not exist."
    with open(module_path, encoding="utf-8") as handle:
        module_text = handle.read()
    assert "go.mongodb.org/mongo-driver" in module_text, "go.mod must use the official MongoDB Go driver."

    with open(EMPLOYEES, encoding="utf-8") as handle:
        original = json.load(handle)

    prefix = "T" + uuid.uuid4().hex[:10]
    manager = prefix + "-M"
    child_a = prefix + "-A"
    child_b = prefix + "-B"
    grandchild = prefix + "-C"
    great_grandchild = prefix + "-D"
    fixture = [
        {"_id": manager, "name": "dynamic manager", "managerId": None},
        {"_id": child_a, "name": "dynamic child A", "managerId": manager},
        {"_id": child_b, "name": "dynamic child B", "managerId": manager},
        {"_id": grandchild, "name": "dynamic grandchild", "managerId": child_a},
        {"_id": great_grandchild, "name": "dynamic great-grandchild", "managerId": grandchild},
        {"_id": prefix + "-X", "name": "unrelated", "managerId": None},
    ]

    try:
        replace_employees(fixture)
        mongo_eval("db.setProfilingLevel(0); db.system.profile.drop(); db.setProfilingLevel(2);")

        result = run_program(manager, 1, 2)
        assert result == expected_subordinates(fixture, manager, 1, 2), (
            "query.go did not honor manager_id, skip, limit, sorting, or exact-document output."
        )
        assert_two_space_indentation()

        second_result = run_program(child_a, 0, 10)
        assert second_result == expected_subordinates(fixture, child_a, 0, 10), (
            "query.go did not correctly traverse indirect subordinates for a second manager."
        )

        profile_result = mongo_eval(
            "JSON.stringify(db.system.profile.find({\"command.aggregate\":\"employees\"})"
            ".sort({$natural:-1}).limit(20).toArray())"
        )
        profiles = parse_shell_json(profile_result.stdout)
        required_stages = {"$graphLookup", "$unwind", "$match", "$sort", "$skip", "$limit"}
        matching_pipeline = False
        for profile in profiles:
            pipeline = profile.get("command", {}).get("pipeline", [])
            stages = {key for stage in pipeline if isinstance(stage, dict) for key in stage}
            if required_stages.issubset(stages):
                matching_pipeline = True
                break
        assert matching_pipeline, (
            "No executed employees aggregation contained the required $graphLookup, flattening, "
            "filtering, sorting, skip, and limit stages."
        )
    finally:
        mongo_eval("db.setProfilingLevel(0)", check=False)
        replace_employees(original)
        subprocess.run(
            [
                "runuser", "-u", "user", "--", "env", "HOME=/home/user",
                "GOCACHE=/home/user/.cache/go-build", "GOMODCACHE=/home/user/go/pkg/mod",
                "go", "run", "query.go", "E2", "1", "3",
            ],
            cwd=APP,
            capture_output=True,
            text=True,
            timeout=180,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
