#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import sqlite3
import subprocess
import sys

import pytest

PIPELINE_DIR = "/home/user/pipeline"
REPORT_PATH = os.path.join(PIPELINE_DIR, "build_report.json")


def load_submission_module(name):
    path = os.path.join(PIPELINE_DIR, name + ".py")
    assert os.path.isfile(path), f"Expected {path} to exist."
    spec = importlib.util.spec_from_file_location("submission_" + name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="session", autouse=True)
def run_build():
    build_path = os.path.join(PIPELINE_DIR, "build.py")
    assert os.path.isfile(build_path), f"Expected build script {build_path} was not found."

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    try:
        completed = subprocess.run(
            [sys.executable, "build.py"],
            cwd=PIPELINE_DIR,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Running python3 build.py timed out; the dependency resolver may still loop indefinitely.")

    assert completed.returncode == 0, (
        "Running python3 build.py did not exit cleanly.\n"
        f"stdout:\n{completed.stdout}\n"
        f"stderr:\n{completed.stderr}"
    )


def test_parser_handles_colons_and_empty_values(tmp_path):
    parser = load_submission_module("parser")
    config_path = tmp_path / "config.txt"
    config_path.write_text(
        "# fixture\n"
        "service: core, api\n"
        "endpoint: http://example.test:8080/v1\n"
        "empty: \n"
    )

    assert parser.parse_config(str(config_path)) == {
        "service": "core, api",
        "endpoint": "http://example.test:8080/v1",
        "empty": "",
    }


def test_resolver_terminates_on_cycles_and_returns_unique_nodes():
    resolver = load_submission_module("resolver")
    edges = {
        "root": ["left", "right"],
        "left": ["root", "leaf"],
        "right": ["left"],
        "leaf": [],
    }
    resolved = resolver.resolve_dependencies("root", edges)
    assert isinstance(resolved, list)
    assert len(resolved) == len(set(resolved)), "The resolver returned duplicate nodes."
    assert set(resolved) == {"root", "left", "right", "leaf"}


def test_get_owners_selects_only_active_rows(tmp_path):
    db_utils = load_submission_module("db_utils")
    db_path = tmp_path / "owners.db"
    conn = sqlite3.connect(str(db_path))
    conn.execute(
        "CREATE TABLE owners (id INTEGER PRIMARY KEY, module_name TEXT, owner TEXT, active INTEGER)"
    )
    conn.executemany(
        "INSERT INTO owners (module_name, owner, active) VALUES (?, ?, ?)",
        [
            ("alpha", "stale-alpha", 0),
            ("alpha", "active-alpha", 1),
            ("beta", "stale-beta", 0),
            ("gamma", "active-gamma", 1),
        ],
    )
    conn.commit()
    conn.close()

    assert db_utils.get_owners(str(db_path), ["alpha", "beta", "gamma"]) == {
        "alpha": "active-alpha",
        "gamma": "active-gamma",
    }


def test_build_report_exists():
    assert os.path.isfile(REPORT_PATH), f"Expected output file {REPORT_PATH} was not found. Did the build script run successfully?"


def test_build_report_valid_json():
    try:
        with open(REPORT_PATH, "r") as f:
            json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {REPORT_PATH} is not valid JSON.")
    except Exception as e:
        pytest.fail(f"Could not read {REPORT_PATH}: {e}")


def test_build_report_dependencies():
    with open(REPORT_PATH, "r") as f:
        data = json.load(f)

    assert "dependencies" in data, "The 'dependencies' key is missing from the build report."

    deps = data["dependencies"]
    assert isinstance(deps, list), "'dependencies' should be a list."

    expected_deps = {"app", "core", "ui", "api", "utils", "frontend_lib", "backend_url"}
    actual_deps = set(deps)

    assert len(deps) == len(actual_deps), "There are duplicate dependencies in the report. The resolver might still have a bug."
    assert actual_deps == expected_deps, f"Dependencies mismatch. Expected {expected_deps}, but got {actual_deps}."


def test_build_report_owners():
    with open(REPORT_PATH, "r") as f:
        data = json.load(f)

    assert "owners" in data, "The 'owners' key is missing from the build report."
    owners = data["owners"]

    assert isinstance(owners, dict), "'owners' should be a dictionary."

    assert owners.get("core") == "bob", "The owner for 'core' is incorrect. It should be the active owner ('bob')."
    assert owners.get("api") == "diana", "The owner for 'api' is incorrect. It should be the active owner ('diana')."
    assert owners.get("backend_url") == "heidi", "The owner for 'backend_url' is incorrect. It should be 'heidi'."

    dependencies = data["dependencies"]
    conn = sqlite3.connect(os.path.join(PIPELINE_DIR, "metadata.db"))
    try:
        expected_owners = {}
        for module in dependencies:
            rows = conn.execute(
                "SELECT owner FROM owners WHERE module_name = ? AND active = 1",
                (module,),
            ).fetchall()
            assert len(rows) == 1, f"Expected exactly one active owner for {module!r} in metadata.db."
            expected_owners[module] = rows[0][0]
    finally:
        conn.close()

    assert set(owners) == set(dependencies), "Every resolved module must have an owner in the report."
    assert owners == expected_owners, "The report does not contain the active database owner for every resolved module."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
