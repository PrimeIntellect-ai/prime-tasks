#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import glob
import json
import os
import shutil
import subprocess
import sys
import sysconfig

import pytest

PROJECT = "/home/user/sec_artifact"
V1_PATH = "/home/user/artifacts_v1.json"
V2_PATH = "/home/user/artifacts_v2.json"
MIGRATE_PATH = "/home/user/migrate.py"
LOG_PATH = "/home/user/verification.log"


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, capture_output=True, **kwargs)


def test_01_setup_py_fixed_and_package_really_builds():
    setup_path = os.path.join(PROJECT, "setup.py")
    assert os.path.isfile(setup_path), f"setup.py is missing at {setup_path}."

    with open(setup_path, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "packaging" in content and "version" in content, "setup.py does not appear to use packaging.version."
    assert "sys.version.split()[0] <" not in content, "setup.py still contains the naive version comparison bug."
    assert "Extension" in content, "setup.py does not import or use setuptools.Extension."
    assert "verifier.c" in content or "sec_artifact/verifier.c" in content, "setup.py does not reference the verifier.c source file."

    # Ensure these are executable setup constructs, not comments or inert strings.
    tree = ast.parse(content, filename=setup_path)
    packaging_imported = any(
        (isinstance(node, ast.Import) and any(alias.name == "packaging" or alias.name.startswith("packaging.") for alias in node.names))
        or (isinstance(node, ast.ImportFrom) and node.module and (node.module == "packaging" or node.module.startswith("packaging.")))
        for node in ast.walk(tree)
    )
    assert packaging_imported, "setup.py does not import packaging.version."

    version_compare = False
    extension_decl = False
    setup_has_ext_modules = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Compare):
            for child in ast.walk(node):
                if isinstance(child, ast.Call):
                    fn = child.func
                    name = fn.id if isinstance(fn, ast.Name) else fn.attr if isinstance(fn, ast.Attribute) else ""
                    if name in {"parse", "Version"}:
                        version_compare = True
        if isinstance(node, ast.Call):
            fn = node.func
            name = fn.id if isinstance(fn, ast.Name) else fn.attr if isinstance(fn, ast.Attribute) else ""
            if name == "Extension":
                values = []
                for child in ast.walk(node):
                    if isinstance(child, ast.Constant) and isinstance(child.value, str):
                        values.append(child.value)
                if "sec_artifact.verifier" in values and any("verifier.c" in value for value in values):
                    extension_decl = True
            if name == "setup" and any(keyword.arg == "ext_modules" for keyword in node.keywords):
                setup_has_ext_modules = True

    assert version_compare, "setup.py does not actively compare parsed versions."
    assert extension_decl, "setup.py does not declare sec_artifact.verifier from verifier.c."
    assert setup_has_ext_modules, "setup.py does not pass extension modules to setup()."

    # Remove any in-tree compiled artifact so installation must build from verifier.c.
    for pattern in (
        os.path.join(PROJECT, "sec_artifact", "verifier*.so"),
        os.path.join(PROJECT, "sec_artifact", "verifier*.pyd"),
    ):
        for path in glob.glob(pattern):
            os.remove(path)
    for path in (os.path.join(PROJECT, "build"), os.path.join(PROJECT, "dist")):
        shutil.rmtree(path, ignore_errors=True)
    for path in glob.glob(os.path.join(PROJECT, "*.egg-info")):
        shutil.rmtree(path, ignore_errors=True)

    result = run([
        sys.executable, "-m", "pip", "install", "--force-reinstall",
        "--no-deps", "--no-cache-dir", PROJECT,
    ], cwd="/tmp")
    assert result.returncode == 0, f"pip install failed:\n{result.stdout}\n{result.stderr}"

    ffi_test = run([
        sys.executable,
        "-c",
        "import importlib.machinery as m; "
        "import sec_artifact.verifier as v; "
        "assert any(v.__file__.endswith(s) for s in m.EXTENSION_SUFFIXES), v.__file__; "
        "assert v.verify_hash('1234567') == 0; "
        "assert v.verify_hash('12345678') == 1; "
        "assert v.verify_hash('abcdefghijklmnop') == 1",
    ], cwd="/tmp")
    assert ffi_test.returncode == 0, f"Compiled extension import/invocation failed:\n{ffi_test.stdout}\n{ffi_test.stderr}"


def test_02_migration_script_exists_and_produces_output_from_input():
    assert os.path.isfile(MIGRATE_PATH), f"Migration script {MIGRATE_PATH} is missing."
    assert os.path.isfile(V1_PATH), f"Original file {V1_PATH} is missing."

    with open(V1_PATH, "rb") as f:
        original = f.read()

    synthetic = {
        "version": "1.0",
        "items": [
            {"id": "runtime-one", "checksum": "87654321", "type": "sha256"},
            {"id": "runtime-two", "checksum": "tiny", "type": "md5"},
        ],
    }

    try:
        with open(V1_PATH, "w") as f:
            json.dump(synthetic, f)
        if os.path.exists(V2_PATH):
            os.remove(V2_PATH)

        result = run([sys.executable, MIGRATE_PATH], cwd="/home/user")
        assert result.returncode == 0, f"migrate.py failed:\n{result.stdout}\n{result.stderr}"
        assert os.path.isfile(V2_PATH), "migrate.py did not create artifacts_v2.json."
        with open(V2_PATH) as f:
            migrated = json.load(f)
        assert migrated == {
            "schema_version": "2.0",
            "artifacts": [
                {"identifier": "runtime-one", "hash_value": "87654321", "hash_type": "sha256"},
                {"identifier": "runtime-two", "hash_value": "tiny", "hash_type": "md5"},
            ],
        }
    finally:
        with open(V1_PATH, "wb") as f:
            f.write(original)
        if os.path.exists(V2_PATH):
            os.remove(V2_PATH)
        restore = run([sys.executable, MIGRATE_PATH], cwd="/home/user")
        assert restore.returncode == 0, f"migrate.py failed on the supplied database:\n{restore.stdout}\n{restore.stderr}"


def test_03_artifacts_v2_schema_and_content():
    v1_path = V1_PATH
    v2_path = V2_PATH

    assert os.path.isfile(v1_path), f"Original file {v1_path} is missing."
    assert os.path.isfile(v2_path), f"Migrated file {v2_path} is missing."

    with open(v1_path, "r") as f:
        v1_data = json.load(f)

    with open(v2_path, "r") as f:
        try:
            v2_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{v2_path} is not valid JSON.")

    assert v2_data.get("schema_version") == "2.0", "schema_version is not '2.0'."
    assert "version" not in v2_data, "Old 'version' key should be removed."
    assert "artifacts" in v2_data, "'artifacts' key is missing."
    assert "items" not in v2_data, "Old 'items' key should be removed."

    v1_items = v1_data.get("items", [])
    v2_artifacts = v2_data.get("artifacts", [])
    assert len(v1_items) == len(v2_artifacts), "Number of artifacts does not match original items."

    for v1_item, v2_item in zip(v1_items, v2_artifacts):
        assert v2_item.get("identifier") == v1_item.get("id"), "identifier does not match original id."
        assert "id" not in v2_item, "Old 'id' key should be removed."
        assert v2_item.get("hash_value") == v1_item.get("checksum"), "hash_value does not match original checksum."
        assert "checksum" not in v2_item, "Old 'checksum' key should be removed."
        assert v2_item.get("hash_type") == v1_item.get("type"), "hash_type does not match original type."
        assert "type" not in v2_item, "Old 'type' key should be removed."


def test_04_cli_check_command_produces_verification_log():
    cli = shutil.which("sec_artifact")
    assert cli, "The sec_artifact console script was not installed."
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    with open(LOG_PATH, "w") as output:
        result = subprocess.run(
            [cli, "check", V2_PATH],
            cwd="/tmp",
            text=True,
            stdout=output,
            stderr=subprocess.PIPE,
        )
    assert result.returncode == 0, f"sec_artifact check failed: {result.stderr}"

    with open(V1_PATH) as f:
        v1_data = json.load(f)
    expected_lines = []
    for item in v1_data.get("items", []):
        status = "VALID" if len(item.get("checksum", "")) >= 8 else "INVALID"
        expected_lines.append(f"Artifact {item['id']} ({item['type']}): {status}")

    with open(LOG_PATH) as f:
        log_content = f.read()
    assert log_content.splitlines() == expected_lines, "verification.log is not the CLI's expected output."


def test_05_verification_log_content():
    log_path = LOG_PATH
    assert os.path.isfile(log_path), f"Verification log {log_path} is missing."

    with open(log_path, "r") as f:
        log_content = f.read()

    # Preserve the original expected-line assertions.
    with open(V1_PATH, "r") as f:
        v1_data = json.load(f)

    for item in v1_data.get("items", []):
        checksum = item.get("checksum", "")
        is_valid = len(checksum) >= 8
        status = "VALID" if is_valid else "INVALID"
        expected_line = f"Artifact {item['id']} ({item['type']}): {status}"
        assert expected_line in log_content, f"Expected line '{expected_line}' not found in verification.log."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
