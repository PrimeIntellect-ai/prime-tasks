#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import stat
import subprocess
import sys
import uuid

import pytest

V2_INDEX_PATH = "/home/user/v2_index.json"
TRANSITIVE_DEPS_PATH = "/home/user/transitive_deps.log"
LEGACY_INDEX_PATH = "/home/user/legacy_index.json"

EXPECTED_LEGACY = '''{
  "packages": {
    "lib-alpha": { "v": "1.0", "deps": ["lib-beta", "lib-gamma"] },
    "lib-beta": { "v": "2.2", "deps": ["lib-delta"] },
    "lib-gamma": { "v": "1.1", "deps": [] },
    "lib-delta": { "v": "3.0", "deps": ["lib-gamma"] },
    "lib-core": { "v": "0.9", "deps": ["lib-alpha", "lib-epsilon"] },
    "lib-epsilon": { "v": "4.1", "deps": [] }
  }
}
'''.encode()


def test_legacy_index_unmodified():
    assert os.path.isfile(LEGACY_INDEX_PATH), f"Legacy index file missing at {LEGACY_INDEX_PATH}"
    with open(LEGACY_INDEX_PATH, "rb") as f:
        raw = f.read()
    assert raw == EXPECTED_LEGACY, "Legacy index file has been modified."
    data = json.loads(raw)
    assert "packages" in data, "Legacy index format has been altered."


def test_v2_index_schema_and_data():
    assert os.path.isfile(V2_INDEX_PATH), f"New index file missing at {V2_INDEX_PATH}"

    with open(V2_INDEX_PATH, "r") as f:
        try:
            v2_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{V2_INDEX_PATH} is not valid JSON.")

    assert "artifacts" in v2_data, f"Key 'artifacts' not found in {V2_INDEX_PATH}"
    artifacts = v2_data["artifacts"]
    assert isinstance(artifacts, list), "'artifacts' should be a list."

    expected_data = {
        "lib-alpha": {"version": "1.0", "dependencies": ["lib-beta", "lib-gamma"]},
        "lib-beta": {"version": "2.2", "dependencies": ["lib-delta"]},
        "lib-gamma": {"version": "1.1", "dependencies": []},
        "lib-delta": {"version": "3.0", "dependencies": ["lib-gamma"]},
        "lib-core": {"version": "0.9", "dependencies": ["lib-alpha", "lib-epsilon"]},
        "lib-epsilon": {"version": "4.1", "dependencies": []},
    }

    assert len(artifacts) == len(expected_data), f"Expected {len(expected_data)} artifacts, found {len(artifacts)}"

    actual_data = {}
    for item in artifacts:
        assert "name" in item, "Artifact missing 'name' key"
        assert "version" in item, f"Artifact {item.get('name')} missing 'version' key"
        assert "dependencies" in item, f"Artifact {item.get('name')} missing 'dependencies' key"
        actual_data[item["name"]] = {
            "version": item["version"],
            "dependencies": item["dependencies"],
        }

    for pkg, details in expected_data.items():
        assert pkg in actual_data, f"Package {pkg} missing from v2_index.json"
        assert actual_data[pkg]["version"] == details["version"], f"Incorrect version for {pkg}"
        assert sorted(actual_data[pkg]["dependencies"]) == sorted(details["dependencies"]), f"Incorrect dependencies for {pkg}"


def test_transitive_deps_log():
    assert os.path.isfile(TRANSITIVE_DEPS_PATH), f"Log file missing at {TRANSITIVE_DEPS_PATH}"

    with open(TRANSITIVE_DEPS_PATH, "r") as f:
        lines = [line.strip() for line in f.read().strip().split("\n") if line.strip()]

    expected_deps = [
        "lib-alpha",
        "lib-beta",
        "lib-delta",
        "lib-epsilon",
        "lib-gamma",
    ]

    assert lines == expected_deps, f"Expected dependencies {expected_deps}, but got {lines}"


def _candidate_scripts():
    roots = ["/home/user", "/workspace", "/root", "/tmp"]
    excluded_dirs = {".cache", ".cargo", ".rustup", ".git", "node_modules", "__pycache__"}
    excluded_files = {
        LEGACY_INDEX_PATH,
        V2_INDEX_PATH,
        TRANSITIVE_DEPS_PATH,
        "/tmp/test_final_state.py",
    }
    candidates = []

    for root in roots:
        if not os.path.isdir(root):
            continue
        for directory, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in excluded_dirs]
            for filename in files:
                path = os.path.abspath(os.path.join(directory, filename))
                if path in excluded_files:
                    continue
                try:
                    info = os.stat(path)
                    if not stat.S_ISREG(info.st_mode) or info.st_size > 2_000_000:
                        continue
                    extension = os.path.splitext(filename)[1].lower()
                    is_script = extension in {".py", ".sh", ".bash", ".js", ".rb", ".pl"}
                    is_executable = os.access(path, os.X_OK)
                    if not (is_script or is_executable):
                        continue
                    if not path.startswith("/home/user/"):
                        with open(path, "rb") as f:
                            sample = f.read(200_000)
                        if b"v2_index" not in sample or b"transitive_deps" not in sample:
                            continue
                    candidates.append(path)
                except (OSError, PermissionError):
                    continue
    return sorted(set(candidates))


def _commands_for(path):
    extension = os.path.splitext(path)[1].lower()
    if extension == ".py":
        base = [sys.executable, path]
    elif extension in {".sh", ".bash"}:
        base = ["bash", path]
    elif extension == ".js":
        node = shutil.which("node") or shutil.which("nodejs")
        if not node:
            return []
        base = [node, path]
    elif extension == ".rb":
        ruby = shutil.which("ruby")
        if not ruby:
            return []
        base = [ruby, path]
    elif extension == ".pl":
        perl = shutil.which("perl")
        if not perl:
            return []
        base = [perl, path]
    else:
        base = [path]
    return [base, base + [V2_INDEX_PATH, TRANSITIVE_DEPS_PATH]]


def test_graph_traversal_script_is_executed_and_uses_v2_index():
    candidates = _candidate_scripts()
    assert candidates, "No graph-traversal test script was found."

    token = uuid.uuid4().hex
    names = [f"dep-{token}-{letter}" for letter in "abcde"]
    a, b, c, d, e = names
    disconnected = f"unused-{token}"
    dynamic_index = {
        "artifacts": [
            {"name": "lib-core", "version": "9.0", "dependencies": [b, a]},
            {"name": a, "version": "1", "dependencies": [d, c]},
            {"name": b, "version": "1", "dependencies": [d]},
            {"name": c, "version": "1", "dependencies": [e]},
            {"name": d, "version": "1", "dependencies": [a]},
            {"name": e, "version": "1", "dependencies": []},
            {"name": disconnected, "version": "1", "dependencies": []},
        ]
    }
    expected = sorted(names)

    with open(V2_INDEX_PATH, "rb") as f:
        original_v2 = f.read()
    original_log = None
    if os.path.exists(TRANSITIVE_DEPS_PATH):
        with open(TRANSITIVE_DEPS_PATH, "rb") as f:
            original_log = f.read()
    with open(LEGACY_INDEX_PATH, "rb") as f:
        original_legacy = f.read()

    passed = None
    try:
        for candidate in candidates:
            for command in _commands_for(candidate):
                with open(V2_INDEX_PATH, "w") as f:
                    json.dump(dynamic_index, f)
                with open(LEGACY_INDEX_PATH, "wb") as f:
                    f.write(original_legacy)
                try:
                    os.remove(TRANSITIVE_DEPS_PATH)
                except FileNotFoundError:
                    pass

                try:
                    subprocess.run(
                        command,
                        cwd=os.path.dirname(candidate) or "/home/user",
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        timeout=10,
                        check=False,
                    )
                except (OSError, subprocess.TimeoutExpired):
                    continue

                if not os.path.isfile(TRANSITIVE_DEPS_PATH):
                    continue
                try:
                    with open(TRANSITIVE_DEPS_PATH, "r") as f:
                        raw_lines = f.read().splitlines()
                except (OSError, UnicodeDecodeError):
                    continue

                if raw_lines == expected:
                    passed = candidate
                    break
            if passed:
                break
    finally:
        with open(V2_INDEX_PATH, "wb") as f:
            f.write(original_v2)
        with open(LEGACY_INDEX_PATH, "wb") as f:
            f.write(original_legacy)
        if original_log is None:
            try:
                os.remove(TRANSITIVE_DEPS_PATH)
            except FileNotFoundError:
                pass
        else:
            with open(TRANSITIVE_DEPS_PATH, "wb") as f:
                f.write(original_log)

    assert passed is not None, (
        "No submitted graph-traversal script produced the derived transitive "
        "dependencies when executed against a verifier-generated v2 index."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
