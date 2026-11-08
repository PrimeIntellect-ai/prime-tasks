#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess
import sys
import tempfile

import pytest

WORKSPACE_DIR = "/home/user/workspace"
BUILDER_DIR = os.path.join(WORKSPACE_DIR, "builder")
BUILD_DIR = os.path.join(BUILDER_DIR, "build")
PACKAGER_BIN = os.path.join(BUILD_DIR, "packager")
LIB_ARCHIVER = os.path.join(BUILD_DIR, "libarchiver.so")
MANIFEST_PY = os.path.join(WORKSPACE_DIR, "manifest.py")
FINAL_MANIFEST = os.path.join(WORKSPACE_DIR, "final_manifest.json")
ARTIFACTS_JSON = os.path.join(WORKSPACE_DIR, "artifacts.json")


def compute_expected_checksum(filepath):
    full_path = os.path.join(WORKSPACE_DIR, filepath)
    if not os.path.isfile(full_path):
        return None
    with open(full_path, "rb") as f:
        data = f.read()
    checksum = 0
    for byte in data:
        checksum ^= byte
    return f"{checksum:02x}"


def xor_bytes(data):
    value = 0
    for byte in data:
        value ^= byte
    return value


def clean_env():
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    return env


def test_build_artifacts_exist():
    assert os.path.isfile(PACKAGER_BIN), f"Expected executable not found: {PACKAGER_BIN}"
    assert os.access(PACKAGER_BIN, os.X_OK), f"File is not executable: {PACKAGER_BIN}"
    assert os.path.isfile(LIB_ARCHIVER), f"Expected shared library not found: {LIB_ARCHIVER}"


def test_packager_runs_without_ld_library_path():
    env = clean_env()
    test_file = os.path.join(BUILDER_DIR, "src", "packager.c")
    try:
        result = subprocess.run(
            [PACKAGER_BIN, test_file], env=env, capture_output=True,
            text=True, cwd=BUILD_DIR, timeout=10
        )
        assert result.returncode == 0, f"packager failed to run. Output: {result.stderr}"
        assert len(result.stdout.strip()) == 2, f"Unexpected output from packager: {result.stdout}"
        assert result.stdout.strip() == compute_expected_checksum("builder/src/packager.c"), \
            f"packager returned an incorrect checksum: {result.stdout}"
    except Exception as e:
        pytest.fail(f"Failed to execute packager: {e}")


def test_packager_correct_on_generated_inputs():
    for _ in range(4):
        data = secrets.token_bytes(137 + secrets.randbelow(500))
        with tempfile.NamedTemporaryFile(dir=WORKSPACE_DIR, delete=False) as f:
            f.write(data)
            path = f.name
        try:
            result = subprocess.run(
                [PACKAGER_BIN, path], env=clean_env(), capture_output=True,
                text=True, cwd=BUILD_DIR, timeout=10
            )
            assert result.returncode == 0, result.stderr
            assert result.stdout.strip() == f"{xor_bytes(data):02x}"
        finally:
            os.unlink(path)


def test_packager_is_dynamically_linked_to_and_uses_archiver():
    dynamic = subprocess.run(
        ["readelf", "-d", PACKAGER_BIN], capture_output=True, text=True, check=True
    ).stdout
    assert "libarchiver.so" in dynamic, "packager has no DT_NEEDED entry for libarchiver.so"

    symbols = subprocess.run(
        ["nm", "-D", PACKAGER_BIN], capture_output=True, text=True, check=True
    ).stdout
    assert any(" U compute_checksum" in line for line in symbols.splitlines()), \
        "packager does not import compute_checksum from the shared library"

    lib_symbols = subprocess.run(
        ["nm", "-D", LIB_ARCHIVER], capture_output=True, text=True, check=True
    ).stdout
    assert any(" compute_checksum" in line and " T " in line for line in lib_symbols.splitlines()), \
        "libarchiver.so does not export compute_checksum"

    marker = 1 + secrets.randbelow(254)
    backup = LIB_ARCHIVER + ".verifier-backup"
    source = LIB_ARCHIVER + ".verifier.c"
    probe = LIB_ARCHIVER + ".verifier-input"
    assert not os.path.exists(backup)
    with open(source, "w") as f:
        f.write(
            "unsigned char compute_checksum(const char *filename) "
            "{ (void)filename; return %d; }\n" % marker
        )
    with open(probe, "wb") as f:
        f.write(secrets.token_bytes(64))

    os.replace(LIB_ARCHIVER, backup)
    try:
        subprocess.run(
            ["gcc", "-shared", "-fPIC", source, "-o", LIB_ARCHIVER],
            check=True, capture_output=True, text=True
        )
        result = subprocess.run(
            [PACKAGER_BIN, probe], env=clean_env(), capture_output=True,
            text=True, cwd=BUILD_DIR, timeout=10
        )
        assert result.returncode == 0, result.stderr
        assert result.stdout.strip() == f"{marker:02x}", \
            "packager did not obtain its checksum from build/libarchiver.so"
    finally:
        if os.path.exists(LIB_ARCHIVER):
            os.unlink(LIB_ARCHIVER)
        os.replace(backup, LIB_ARCHIVER)
        for path in (source, probe):
            if os.path.exists(path):
                os.unlink(path)


def test_manifest_py_exists():
    assert os.path.isfile(MANIFEST_PY), f"Python script not found: {MANIFEST_PY}"


def test_final_manifest_json():
    assert os.path.isfile(FINAL_MANIFEST), f"Final manifest not found: {FINAL_MANIFEST}"

    with open(FINAL_MANIFEST, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"final_manifest.json is not valid JSON: {e}")

    assert "version" in data, "Missing 'version' in final_manifest.json"
    assert data["version"] == 2, f"Expected version 2, got {data.get('version')}"
    assert "artifacts" in data, "Missing 'artifacts' in final_manifest.json"
    artifacts = data["artifacts"]

    expected_items = ["item-1", "item-2"]
    for item in expected_items:
        assert item in artifacts, f"Missing {item} in artifacts"

    item1 = artifacts["item-1"]
    assert item1.get("file") == "builder/src/archiver.c", "Incorrect file for item-1"
    assert item1.get("category") == "source", "Incorrect category for item-1"
    expected_checksum_1 = compute_expected_checksum(item1["file"])
    assert item1.get("checksum") == expected_checksum_1, \
        f"Incorrect checksum for item-1. Expected {expected_checksum_1}, got {item1.get('checksum')}"

    item2 = artifacts["item-2"]
    assert item2.get("file") == "builder/src/packager.c", "Incorrect file for item-2"
    assert item2.get("category") == "source", "Incorrect category for item-2"
    expected_checksum_2 = compute_expected_checksum(item2["file"])
    assert item2.get("checksum") == expected_checksum_2, \
        f"Incorrect checksum for item-2. Expected {expected_checksum_2}, got {item2.get('checksum')}"


def test_manifest_executes_packager_for_dynamic_manifest():
    token = secrets.token_hex(8)
    input_dir = os.path.join(WORKSPACE_DIR, ".verifier_inputs_" + token)
    os.mkdir(input_dir)

    rows = []
    expected = {}
    target_paths = set()
    for index in range(3):
        data = secrets.token_bytes(91 + index * 53 + secrets.randbelow(40))
        relative_path = os.path.relpath(os.path.join(input_dir, f"payload_{index}.bin"), WORKSPACE_DIR)
        absolute_path = os.path.join(WORKSPACE_DIR, relative_path)
        with open(absolute_path, "wb") as f:
            f.write(data)
        artifact_id = f"generated-{token}-{index}"
        category = f"category-{index}-{token}"
        rows.append({"id": artifact_id, "filepath": relative_path, "type": category})
        target_paths.add(os.path.realpath(absolute_path))
        expected[artifact_id] = {
            "file": relative_path,
            "category": category,
            "raw_checksum": xor_bytes(data),
        }

    with open(ARTIFACTS_JSON, "rb") as f:
        old_artifacts = f.read()
    old_final = None
    if os.path.exists(FINAL_MANIFEST):
        with open(FINAL_MANIFEST, "rb") as f:
            old_final = f.read()

    real_packager = PACKAGER_BIN + ".verifier-real"
    log_path = os.path.join(input_dir, "calls.jsonl")
    mask = 1 + secrets.randbelow(255)
    assert not os.path.exists(real_packager)

    os.replace(PACKAGER_BIN, real_packager)
    try:
        wrapper = f'''#!/usr/bin/env python3
import json, os, subprocess, sys
real = {real_packager!r}
log = {log_path!r}
env = os.environ.copy()
env.pop("LD_LIBRARY_PATH", None)
with open(log, "a") as f:
    f.write(json.dumps({{"cwd": os.getcwd(), "args": sys.argv[1:]}}) + "\\n")
r = subprocess.run([real] + sys.argv[1:], env=env, capture_output=True, text=True)
if r.returncode != 0:
    sys.stderr.write(r.stderr)
    raise SystemExit(r.returncode)
try:
    value = int(r.stdout.strip(), 16) ^ {mask}
except Exception:
    sys.stderr.write("invalid real packager output: " + r.stdout)
    raise SystemExit(90)
print(f"{{value:02x}}")
'''
        with open(PACKAGER_BIN, "w") as f:
            f.write(wrapper)
        os.chmod(PACKAGER_BIN, 0o755)

        with open(ARTIFACTS_JSON, "w") as f:
            json.dump(rows, f)
        if os.path.exists(FINAL_MANIFEST):
            os.unlink(FINAL_MANIFEST)

        result = subprocess.run(
            [sys.executable, MANIFEST_PY], cwd=WORKSPACE_DIR,
            env=clean_env(), capture_output=True, text=True, timeout=20
        )
        assert result.returncode == 0, \
            f"manifest.py failed on generated input: stdout={result.stdout!r} stderr={result.stderr!r}"
        assert os.path.isfile(FINAL_MANIFEST), "manifest.py did not write final_manifest.json"

        with open(FINAL_MANIFEST) as f:
            generated = json.load(f)
        assert generated.get("version") == 2
        assert set(generated.get("artifacts", {})) == set(expected)
        for artifact_id, info in expected.items():
            actual = generated["artifacts"][artifact_id]
            assert actual.get("file") == info["file"]
            assert actual.get("category") == info["category"]
            assert actual.get("checksum") == f"{info['raw_checksum'] ^ mask:02x}", \
                "manifest.py did not use the checksum returned by packager"

        assert os.path.isfile(log_path), "manifest.py never executed the packager path"
        invoked_paths = set()
        with open(log_path) as f:
            for line in f:
                call = json.loads(line)
                assert call["args"], "packager was invoked without an artifact path"
                argument = call["args"][0]
                if os.path.isabs(argument):
                    invoked_paths.add(os.path.realpath(argument))
                else:
                    invoked_paths.add(os.path.realpath(os.path.join(call["cwd"], argument)))
        assert target_paths.issubset(invoked_paths), \
            "manifest.py did not invoke packager for every generated artifact file"
    finally:
        if os.path.exists(PACKAGER_BIN):
            os.unlink(PACKAGER_BIN)
        if os.path.exists(real_packager):
            os.replace(real_packager, PACKAGER_BIN)
        with open(ARTIFACTS_JSON, "wb") as f:
            f.write(old_artifacts)
        if old_final is None:
            if os.path.exists(FINAL_MANIFEST):
                os.unlink(FINAL_MANIFEST)
        else:
            with open(FINAL_MANIFEST, "wb") as f:
                f.write(old_final)
        shutil.rmtree(input_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
