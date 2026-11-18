#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile
import json
import py_compile
import tempfile
import subprocess
import sys
import secrets

ARTIFACT = "/home/user/migration/artifact.tar.gz"


def load_json_file(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def assert_exact_migration(data, source):
    assert isinstance(data, list), "output.json should contain a list of objects."

    expected = {
        int(k): {
            "new_id": int(k),
            "full_name": v["name"],
            "is_admin": v["role"] == "Admin",
        }
        for k, v in source.items()
    }

    assert len(data) == len(expected), (
        f"Migration produced {len(data)} records; expected {len(expected)}."
    )

    found = {}
    for item in data:
        assert isinstance(item, dict), "Each output record must be an object."
        assert set(item) == {"new_id", "full_name", "is_admin"}, (
            f"Output record has incorrect fields: {set(item)}"
        )
        assert type(item["new_id"]) is int, "new_id must be an integer."
        assert isinstance(item["full_name"], str), "full_name must be a string."
        assert type(item["is_admin"]) is bool, "is_admin must be a boolean."
        assert item["new_id"] not in found, "Duplicate new_id in migration output."
        found[item["new_id"]] = item

    assert found == expected, f"Migration output is incorrect. Expected {expected}, got {found}."


def test_artifact_exists():
    artifact = "/home/user/migration/artifact.tar.gz"
    assert os.path.exists(artifact), f"Artifact {artifact} not found."
    assert os.path.isfile(artifact), f"{artifact} is not a file."
    assert tarfile.is_tarfile(artifact), f"{artifact} is not a valid tar archive."


def test_artifact_contents():
    artifact = "/home/user/migration/artifact.tar.gz"
    assert os.path.exists(artifact), "Artifact not found."

    with tarfile.open(artifact, "r:gz") as tar:
        names = tar.getnames()
        expected_names = {"version.info", "migrate.py", "output.json"}
        assert set(names) == expected_names, f"Tarball contains incorrect files. Expected {expected_names}, got {set(names)}"
        assert len(names) == 3, f"Tarball must contain exactly three entries, got {len(names)}."
        assert all(member.isfile() for member in tar.getmembers()), "All artifact entries must be regular files."


def test_version_info_content():
    artifact = "/home/user/migration/artifact.tar.gz"
    assert os.path.exists(artifact), "Artifact not found."

    with tarfile.open(artifact, "r:gz") as tar:
        with tar.extractfile("version.info") as f:
            content = f.read().decode('utf-8').strip()
            assert content == "v2.0.1", f"Incorrect version in version.info: expected 'v2.0.1', got '{content}'"


def test_output_json_content():
    artifact = "/home/user/migration/artifact.tar.gz"
    assert os.path.exists(artifact), "Artifact not found."

    with tarfile.open(artifact, "r:gz") as tar:
        with tar.extractfile("output.json") as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError:
                assert False, "output.json is not valid JSON."

            assert isinstance(data, list), "output.json should contain a list of objects."
            assert len(data) == 3, f"output.json should have 3 records, found {len(data)}."

            expected_ids = {101, 102, 103}
            found_ids = set()
            for item in data:
                assert "new_id" in item, "Missing 'new_id' in output record."
                assert "full_name" in item, "Missing 'full_name' in output record."
                assert "is_admin" in item, "Missing 'is_admin' in output record."
                found_ids.add(item["new_id"])

            assert expected_ids == found_ids, f"Output JSON missing correct new_id fields. Expected {expected_ids}, got {found_ids}."

            source = load_json_file("/home/user/migration/input.json")
            assert_exact_migration(data, source)


def test_migrate_py_syntax():
    artifact = "/home/user/migration/artifact.tar.gz"
    assert os.path.exists(artifact), "Artifact not found."

    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(artifact, "r:gz") as tar:
            tar.extract("migrate.py", path=tmpdir)

        extracted_script = os.path.join(tmpdir, "migrate.py")
        try:
            py_compile.compile(extracted_script, doraise=True)
        except py_compile.PyCompileError as e:
            assert False, f"migrate.py has Python 3 syntax errors: {e}"


def test_migrate_py_executes_schema_transformation():
    nonce = secrets.token_hex(12)
    ids = set()
    while len(ids) < 4:
        ids.add(20000 + secrets.randbelow(800000))
    ids = list(ids)
    source = {
        str(ids[0]): {"name": f"Dynamic Admin {nonce}", "role": "Admin"},
        str(ids[1]): {"name": f"Dynamic User {nonce}", "role": "User"},
        str(ids[2]): {"name": f"Dynamic Other {nonce}", "role": "Owner"},
        str(ids[3]): {"name": f"Dynamic Case {nonce}", "role": "admin"},
    }

    with tempfile.TemporaryDirectory() as tmpdir:
        script = os.path.join(tmpdir, "migrate.py")
        input_path = os.path.join(tmpdir, "generated-input.json")
        output_path = os.path.join(tmpdir, "generated-output.json")

        with tarfile.open(ARTIFACT, "r:gz") as tar:
            member = tar.getmember("migrate.py")
            assert member.isfile(), "migrate.py in the artifact must be a regular file."
            with tar.extractfile(member) as src, open(script, "wb") as dst:
                dst.write(src.read())

        with open(input_path, "w", encoding="utf-8") as f:
            json.dump(source, f)

        result = subprocess.run(
            [sys.executable, script, input_path, output_path],
            cwd=tmpdir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"Archived migrate.py failed under Python 3. stdout={result.stdout!r}, "
            f"stderr={result.stderr!r}"
        )
        assert os.path.isfile(output_path), "migrate.py did not create the requested output file."

        try:
            generated = load_json_file(output_path)
        except json.JSONDecodeError as e:
            assert False, f"migrate.py generated invalid JSON: {e}"
        assert_exact_migration(generated, source)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
