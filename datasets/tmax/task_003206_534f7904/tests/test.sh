#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import sqlite3
import subprocess
import tempfile
from pathlib import Path

import pytest

REPORT = Path("/home/user/violation_report.json")
DB = Path("/home/user/employees.db")
TTL = Path("/home/user/resources.ttl")
PROJECT = Path("/home/user/compliance_auditor")


def load_report(path):
    assert path.exists(), f"Violation report not found at {path}"
    with path.open("r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse JSON in {path}: {e}")


def test_complete_rust_application_and_report():
    # Preserve the original verifier's assertions against the supplied inputs.
    data = load_report(REPORT)
    assert "violators" in data, "JSON must contain a 'violators' key at the root level."

    violators = data["violators"]
    assert isinstance(violators, list), "'violators' must be a list."

    expected_violators = [
        {
            "name": "Charlie",
            "role_uri": "http://example.org/role/TempDev"
        },
        {
            "name": "Eve",
            "role_uri": "http://example.org/role/SuperVendor"
        }
    ]
    expected_violators_sorted = sorted(expected_violators, key=lambda x: x["name"])
    assert len(violators) == len(expected_violators_sorted), f"Expected {len(expected_violators_sorted)} violators, but found {len(violators)}."
    names = [v.get("name", "") for v in violators]
    assert names == sorted(names), "The violators list must be sorted alphabetically by name."
    for i, expected in enumerate(expected_violators_sorted):
        actual = violators[i]
        assert actual.get("name") == expected["name"], f"Expected violator name '{expected['name']}', got '{actual.get('name')}'"
        assert actual.get("role_uri") == expected["role_uri"], f"Expected role_uri '{expected['role_uri']}' for {expected['name']}, got '{actual.get('role_uri')}'"

    # Verify that the requested Rust project and direct crate dependencies exist.
    manifest = PROJECT / "Cargo.toml"
    assert PROJECT.is_dir(), f"Rust project not found at {PROJECT}"
    assert manifest.is_file(), f"Cargo manifest not found at {manifest}"
    rust_sources = list(PROJECT.rglob("*.rs"))
    assert rust_sources, "The project contains no Rust source files"

    metadata_result = subprocess.run(
        ["/opt/cargo/bin/cargo", "metadata", "--format-version", "1", "--no-deps", "--manifest-path", str(manifest)],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert metadata_result.returncode == 0, f"Invalid Cargo project: {metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)
    project_manifest = str(manifest.resolve())
    packages = [p for p in metadata.get("packages", []) if str(Path(p["manifest_path"]).resolve()) == project_manifest]
    assert packages, "Cargo metadata does not contain the compliance_auditor package"
    dependency_names = {d["name"].replace("-", "_") for d in packages[0].get("dependencies", [])}
    assert "rusqlite" in dependency_names, "The Rust project must depend on rusqlite"
    assert "oxigraph" in dependency_names, "The Rust project must depend on oxigraph"

    source_text = "\n".join(p.read_text(errors="replace") for p in rust_sources)
    assert "rusqlite" in source_text, "Rust source does not use rusqlite"
    assert "oxigraph" in source_text, "Rust source does not use oxigraph"
    assert "canRead" in source_text and "inheritsFrom" in source_text, "Rust source does not contain the required ACL/inheritance query"
    assert "SELECT" in source_text.upper(), "Rust source does not appear to construct a SPARQL SELECT query"

    # Replace both inputs with an independently constructed case, then actually
    # execute the submitted application. This detects hardcoded report writers
    # and exercises direct access, multi-level inheritance, filtering, and sorting.
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        db_backup = td / "employees.db"
        ttl_backup = td / "resources.ttl"
        report_backup = td / "violation_report.json"
        shutil.copy2(DB, db_backup)
        shutil.copy2(TTL, ttl_backup)
        if REPORT.exists():
            shutil.copy2(REPORT, report_backup)

        try:
            for suffix in ("", "-wal", "-shm"):
                candidate = Path(str(DB) + suffix)
                if candidate.exists():
                    candidate.unlink()

            connection = sqlite3.connect(DB)
            connection.executescript("""
                CREATE TABLE employee (id INTEGER PRIMARY KEY, name TEXT, department TEXT);
                CREATE TABLE employee_roles (emp_id INTEGER, role_uri TEXT);
                INSERT INTO employee VALUES (1, 'Zoe', 'Contractor');
                INSERT INTO employee VALUES (2, 'Aaron', 'Contractor');
                INSERT INTO employee VALUES (3, 'Noah', 'Contractor');
                INSERT INTO employee VALUES (4, 'Mia', 'Contractor');
                INSERT INTO employee VALUES (5, 'Engineering Intruder', 'Engineering');
                INSERT INTO employee VALUES (6, 'Roleless Contractor', 'Contractor');
                INSERT INTO employee_roles VALUES (1, 'http://example.org/role/ChainStart');
                INSERT INTO employee_roles VALUES (2, 'http://example.org/role/DirectReader');
                INSERT INTO employee_roles VALUES (3, 'http://example.org/role/SafeRole');
                INSERT INTO employee_roles VALUES (4, 'http://example.org/role/SplitStart');
                INSERT INTO employee_roles VALUES (5, 'http://example.org/role/DirectReader');
            """)
            connection.commit()
            connection.close()

            TTL.write_text("""@prefix ex: <http://example.org/> .
@prefix role: <http://example.org/role/> .

role:DirectReader ex:canRead ex:CustomerData .
role:ChainStart ex:inheritsFrom role:ChainMiddle .
role:ChainMiddle ex:inheritsFrom role:ChainEnd .
role:ChainEnd ex:canRead ex:CustomerData .
role:SplitStart ex:inheritsFrom role:SafeParent .
role:SplitStart ex:inheritsFrom role:RiskMiddle .
role:RiskMiddle ex:inheritsFrom role:RiskEnd .
role:RiskEnd ex:canRead ex:CustomerData .
role:SafeParent ex:canRead ex:PublicData .
role:SafeRole ex:canRead ex:PublicData .
""")
            if REPORT.exists():
                REPORT.unlink()

            run_result = subprocess.run(
                [
                    "runuser", "-u", "user", "--", "env",
                    "HOME=/home/user",
                    "RUSTUP_HOME=/opt/rust",
                    "CARGO_HOME=/opt/cargo",
                    "PATH=/opt/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
                    "/opt/cargo/bin/cargo", "run", "--quiet", "--manifest-path", str(manifest)
                ],
                cwd=PROJECT,
                capture_output=True,
                text=True,
                timeout=300,
            )
            assert run_result.returncode == 0, (
                "The Rust application failed on verification inputs.\n"
                f"stdout:\n{run_result.stdout}\nstderr:\n{run_result.stderr}"
            )

            generated = load_report(REPORT)
            expected_dynamic = {
                "violators": [
                    {"name": "Aaron", "role_uri": "http://example.org/role/DirectReader"},
                    {"name": "Mia", "role_uri": "http://example.org/role/SplitStart"},
                    {"name": "Zoe", "role_uri": "http://example.org/role/ChainStart"}
                ]
            }
            assert generated == expected_dynamic, f"Incorrect report for verification inputs: {generated!r}"
            dynamic_names = [v["name"] for v in generated["violators"]]
            assert dynamic_names == sorted(dynamic_names), "The generated violators are not alphabetically sorted"
        finally:
            for suffix in ("", "-wal", "-shm"):
                candidate = Path(str(DB) + suffix)
                if candidate.exists():
                    candidate.unlink()
            shutil.copy2(db_backup, DB)
            shutil.copy2(ttl_backup, TTL)
            if REPORT.exists():
                REPORT.unlink()
            if report_backup.exists():
                shutil.copy2(report_backup, REPORT)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
