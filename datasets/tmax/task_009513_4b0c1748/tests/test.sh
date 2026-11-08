#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib
import json
import os
import secrets
import subprocess
import sys

import pytest
from packaging.requirements import Requirement
from importlib import metadata

APP_DIR = "/home/user/app"


def test_test_main_unmodified():
    test_main_path = os.path.join(APP_DIR, "test_main.py")
    assert os.path.isfile(test_main_path), "test_main.py is missing."

    expected_content = """from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_read_item():
    response = client.get("/items/42")
    assert response.status_code == 200
    assert response.json() == {"item_id": 42, "name": "Item 42", "is_offer": None}

def test_create_item():
    response = client.post("/items/", json={"name": "Screwdriver", "price": 12.5})
    assert response.status_code == 200
    assert response.json() == {"name": "Screwdriver", "price": 12.5, "tax": 1.25}

def test_create_item_no_tax():
    response = client.post("/items/", json={"name": "Hammer", "price": 10.0, "tax": 0.0})
    assert response.status_code == 200
    assert response.json() == {"name": "Hammer", "price": 10.0, "tax": 0.0}"""

    with open(test_main_path, "r") as f:
        content = f.read()

    assert content.strip() == expected_content.strip(), "test_main.py was modified, which is not allowed."


def test_json_report():
    report_path = "/home/user/test_report.json"
    assert os.path.isfile(report_path), "The file /home/user/test_report.json is missing. Did you run pytest with the correct flags?"

    with open(report_path, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("test_report.json is not a valid JSON file.")

    assert "summary" in report, "The JSON report does not contain a 'summary' section."
    summary = report["summary"]
    passed = summary.get("passed", 0)
    failed = summary.get("failed", 0)

    assert passed == 3, f"Expected exactly 3 tests to pass, but found {passed} passed tests."
    assert failed == 0, f"Expected 0 failed tests, but found {failed} failed tests."

    tests = report.get("tests")
    assert isinstance(tests, list), "The JSON report does not contain test results."
    expected_names = {"test_read_item", "test_create_item", "test_create_item_no_tax"}
    reported = {
        entry.get("nodeid", "").split("::")[-1]: entry.get("outcome")
        for entry in tests
    }
    assert set(reported) == expected_names, "The JSON report does not describe exactly the required three tests."
    assert all(outcome == "passed" for outcome in reported.values()), "The JSON report contains a non-passing test."


def test_dependencies_are_installed_and_compatible():
    requirements_path = os.path.join(APP_DIR, "requirements.txt")
    assert os.path.isfile(requirements_path), "requirements.txt is missing."

    requirements = []
    with open(requirements_path, "r") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            assert not line.startswith("-"), "requirements.txt must contain installable package requirements."
            requirements.append(Requirement(line))

    required_names = {req.name.lower().replace("_", "-") for req in requirements}
    for package in ("fastapi", "pydantic", "pytest", "httpx", "pytest-json-report"):
        assert package in required_names, f"requirements.txt is missing {package}."

    for req in requirements:
        try:
            installed = metadata.version(req.name)
        except metadata.PackageNotFoundError:
            pytest.fail(f"Required package {req.name} is not installed.")
        assert not req.specifier or installed in req.specifier, (
            f"Installed {req.name} {installed} does not satisfy {req.specifier}."
        )

    result = subprocess.run(
        [sys.executable, "-m", "pip", "check"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, "Installed dependencies are incompatible:\n" + result.stdout
    metadata.version("pytest-json-report")


def test_real_project_suite_passes():
    result = subprocess.run(
        [sys.executable, "-m", "pytest", "-q", "test_main.py"],
        cwd=APP_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, "The real application test suite failed:\n" + result.stdout


def test_application_on_independent_inputs():
    main_path = os.path.join(APP_DIR, "main.py")
    assert os.path.isfile(main_path), "main.py is missing."

    sys.path.insert(0, APP_DIR)
    sys.modules.pop("main", None)
    module = importlib.import_module("main")

    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    assert isinstance(module.app, FastAPI), "main.py does not expose a FastAPI application named app."
    client = TestClient(module.app)

    item_id = 1000 + secrets.randbelow(8000)
    response = client.get(f"/items/{item_id}")
    assert response.status_code == 200
    assert response.json() == {
        "item_id": item_id,
        "name": f"Item {item_id}",
        "is_offer": None,
    }

    name = "Item-" + secrets.token_hex(6)
    price = float(20 + secrets.randbelow(200))
    response = client.post("/items/", json={"name": name, "price": price})
    assert response.status_code == 200
    assert response.json() == {"name": name, "price": price, "tax": price * 0.10}

    explicit_tax = float(1 + secrets.randbelow(20))
    response = client.post(
        "/items/",
        json={"name": name, "price": price, "tax": explicit_tax},
    )
    assert response.status_code == 200
    assert response.json() == {"name": name, "price": price, "tax": explicit_tax}
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
