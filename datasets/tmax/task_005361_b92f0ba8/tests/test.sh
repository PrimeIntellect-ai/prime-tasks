#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
import tempfile
import uuid

ARTIFACTS_DIR = "/home/user/artifacts"
BUILD_ORDER_FILE = "/home/user/build_order.txt"


def test_libB_schema_migration():
    filepath = os.path.join(ARTIFACTS_DIR, "libB.json")
    assert os.path.isfile(filepath), f"File {filepath} is missing."
    with open(filepath, "r") as f:
        data = json.load(f)

    assert data.get("schema_version") == 2, f"libB.json schema_version should be 2, got {data.get('schema_version')}"
    assert "needs" not in data, "libB.json should not contain 'needs' key."
    assert "requires" in data, "libB.json should contain 'requires' key."
    assert data.get("requires") == ["A"], f"libB.json requires should be ['A'], got {data.get('requires')}"
    assert data.get("name") == "libB", "libB.json name should remain 'libB'"
    assert data.get("provides") == ["B"], "libB.json provides should remain ['B']"


def test_libD_dependency_fix():
    filepath = os.path.join(ARTIFACTS_DIR, "libD.json")
    assert os.path.isfile(filepath), f"File {filepath} is missing."
    with open(filepath, "r") as f:
        data = json.load(f)

    assert data.get("schema_version") == 2, "libD.json schema_version should be 2"
    assert "requires" in data, "libD.json should contain 'requires' key."
    assert data.get("requires") == ["A"], f"libD.json requires should be ['A'] instead of ['C'], got {data.get('requires')}"


def test_build_order_output():
    assert os.path.isfile(BUILD_ORDER_FILE), f"File {BUILD_ORDER_FILE} is missing."
    with open(BUILD_ORDER_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_order = ["libA", "libB", "libD", "libC"]
    assert lines == expected_order, f"Build order is incorrect. Expected {expected_order}, got {lines}"


def find_python_scripts():
    scripts = []
    for root, dirs, files in os.walk("/home/user"):
        if root == ARTIFACTS_DIR or root.startswith(ARTIFACTS_DIR + os.sep):
            dirs[:] = []
            continue
        dirs[:] = [d for d in dirs if d not in {".cache", "__pycache__"}]
        for filename in files:
            path = os.path.join(root, filename)
            if not os.path.isfile(path):
                continue
            is_python = filename.endswith(".py")
            if not is_python:
                try:
                    with open(path, "rb") as f:
                        first_line = f.readline(256).lower()
                    is_python = first_line.startswith(b"#!") and b"python" in first_line
                except OSError:
                    pass
            if is_python:
                scripts.append(path)
    return sorted(scripts)


def derive_order(records):
    remaining = list(records)
    provided = set()
    result = []
    while remaining:
        ready = [r for r in remaining if set(r["requires"]).issubset(provided)]
        assert ready, "Verifier fixture unexpectedly contains a dependency cycle"
        chosen = min(ready, key=lambda r: r["name"])
        result.append(chosen["name"])
        provided.update(chosen["provides"])
        remaining.remove(chosen)
    return result


def test_python_script_executes_and_resolves_dependencies():
    scripts = find_python_scripts()
    assert scripts, "No Python build-order script was found under /home/user."

    token = uuid.uuid4().hex
    symbols = ["A"] + [f"sym_{token}_{i}" for i in range(6)]
    names = [f"artifact_{uuid.uuid4().hex}" for _ in range(6)]
    records = [
        {"name": names[0], "schema_version": 2, "provides": [symbols[0]], "requires": []},
        {"name": "libD", "schema_version": 2, "provides": [symbols[1]], "requires": [symbols[0]]},
        {"name": names[1], "schema_version": 2, "provides": [symbols[2]], "requires": [symbols[0]]},
        {"name": names[2], "schema_version": 2, "provides": [symbols[3]], "requires": [symbols[2]]},
        {"name": names[3], "schema_version": 2, "provides": [symbols[4]], "requires": []},
        {"name": names[4], "schema_version": 2, "provides": [symbols[5]], "requires": [symbols[4]]},
        {"name": names[5], "schema_version": 2, "provides": [symbols[6]], "requires": [symbols[1], symbols[3], symbols[5]]},
    ]
    expected = derive_order(records)

    with tempfile.TemporaryDirectory(prefix="verifier-") as tempdir:
        original_artifacts = os.path.join(tempdir, "original_artifacts")
        fixture_artifacts = os.path.join(tempdir, "fixture_artifacts")
        shutil.copytree(ARTIFACTS_DIR, original_artifacts)
        os.mkdir(fixture_artifacts)
        for index, record in enumerate(records):
            with open(os.path.join(fixture_artifacts, f"record_{index}.json"), "w") as f:
                json.dump(record, f)

        output_existed = os.path.isfile(BUILD_ORDER_FILE)
        original_output = os.path.join(tempdir, "original_build_order.txt")
        if output_existed:
            shutil.copy2(BUILD_ORDER_FILE, original_output)

        successes = []
        try:
            for script in scripts:
                if os.path.exists(ARTIFACTS_DIR):
                    shutil.rmtree(ARTIFACTS_DIR)
                shutil.copytree(fixture_artifacts, ARTIFACTS_DIR)
                if os.path.exists(BUILD_ORDER_FILE):
                    os.remove(BUILD_ORDER_FILE)

                try:
                    completed = subprocess.run(
                        ["python3", script],
                        cwd="/home/user",
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=10,
                    )
                except (OSError, subprocess.TimeoutExpired):
                    continue

                if completed.returncode != 0 or not os.path.isfile(BUILD_ORDER_FILE):
                    continue
                try:
                    with open(BUILD_ORDER_FILE, "r") as f:
                        actual = [line.strip() for line in f if line.strip()]
                except OSError:
                    continue
                if actual == expected:
                    successes.append(script)
                    break
        finally:
            if os.path.exists(ARTIFACTS_DIR):
                shutil.rmtree(ARTIFACTS_DIR)
            shutil.copytree(original_artifacts, ARTIFACTS_DIR)
            if output_existed:
                shutil.copy2(original_output, BUILD_ORDER_FILE)
            elif os.path.exists(BUILD_ORDER_FILE):
                os.remove(BUILD_ORDER_FILE)

        assert successes, (
            "No submitted Python script ran cleanly and generated the dependency-derived "
            "build order for an independent artifact set."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
