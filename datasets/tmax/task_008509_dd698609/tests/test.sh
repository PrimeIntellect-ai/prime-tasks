#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import shutil
import subprocess
import sys
import tarfile
import uuid

import pytest


def test_renamed_files():
    expected_files = [
        "/home/user/server_configs/region_us/db_config.json",
        "/home/user/server_configs/region_us/web_config.json",
        "/home/user/server_configs/region_eu/app1/settings.xml",
        "/home/user/server_configs/region_eu/app1/legacy_cfg.json",
        "/home/user/server_configs/users.csv",
    ]

    unexpected_files = [
        "/home/user/server_configs/region_us/db_config.JSON",
        "/home/user/server_configs/region_us/web_config.JSON",
        "/home/user/server_configs/region_eu/app1/settings.XML",
        "/home/user/server_configs/region_eu/app1/legacy_cfg.JSON",
        "/home/user/server_configs/users.CSV",
    ]

    for file_path in expected_files:
        assert os.path.isfile(file_path), f"Expected renamed file is missing: {file_path}"

    for file_path in unexpected_files:
        assert not os.path.exists(file_path), f"Old file with uppercase extension still exists: {file_path}"


def test_json_contents():
    db_config_path = "/home/user/server_configs/region_us/db_config.json"
    with open(db_config_path, "r") as f:
        db_config = json.load(f)
    assert db_config.get("status") == "archived", "db_config.json should have status 'archived'"

    web_config_path = "/home/user/server_configs/region_us/web_config.json"
    with open(web_config_path, "r") as f:
        web_config = json.load(f)
    assert web_config.get("status") == "active", "web_config.json should have status 'active'"

    legacy_cfg_path = "/home/user/server_configs/region_eu/app1/legacy_cfg.json"
    with open(legacy_cfg_path, "r") as f:
        legacy_cfg = json.load(f)
    assert legacy_cfg.get("status") == "archived", "legacy_cfg.json should have status 'archived'"


def test_manifest_creation():
    manifest_path = "/home/user/manifest.csv"
    assert os.path.isfile(manifest_path), f"Manifest file missing: {manifest_path}"

    with open(manifest_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "/home/user/server_configs/region_eu/app1/legacy_cfg.json",
        "/home/user/server_configs/region_us/db_config.json",
    ]

    assert lines == expected_lines, f"Manifest contents are incorrect. Expected {expected_lines}, got {lines}"


def test_incremental_backup():
    backup_path = "/home/user/incremental_backup.tar.gz"
    snapshot_path = "/home/user/backup.snar"
    assert os.path.isfile(backup_path), f"Incremental backup missing: {backup_path}"
    assert tarfile.is_tarfile(backup_path), f"File is not a valid tar archive: {backup_path}"
    assert os.path.isfile(snapshot_path), f"Tar snapshot file missing: {snapshot_path}"
    assert os.path.getsize(snapshot_path) > 0, "Tar snapshot file is empty"

    with open(snapshot_path, "rb") as f:
        snapshot_header = f.read(32)
    assert snapshot_header.startswith(b"GNU tar-"), "backup.snar is not a GNU tar snapshot file"

    try:
        with tarfile.open(backup_path, "r:gz") as tar:
            members = tar.getmembers()
            assert len(members) > 0, "Tar archive is empty"
            assert any(member.type == b"D" for member in members), (
                "Archive lacks GNU incremental directory records; it was not created as a listed-incremental tar"
            )

            by_name = {}
            for member in members:
                name = member.name
                while name.startswith("./"):
                    name = name[2:]
                by_name[name.rstrip("/")] = member

            expected_files = [
                "server_configs/region_us/db_config.json",
                "server_configs/region_us/web_config.json",
                "server_configs/region_eu/app1/settings.xml",
                "server_configs/region_eu/app1/legacy_cfg.json",
                "server_configs/users.csv",
            ]
            for name in expected_files:
                assert name in by_name, f"Incremental archive is missing changed file: {name}"
                assert by_name[name].isfile(), f"Archived path is not a regular file: {name}"

            for old_name in [
                "server_configs/region_us/db_config.JSON",
                "server_configs/region_us/web_config.JSON",
                "server_configs/region_eu/app1/settings.XML",
                "server_configs/region_eu/app1/legacy_cfg.JSON",
                "server_configs/users.CSV",
            ]:
                assert old_name not in by_name, f"Archive contains obsolete uppercase path: {old_name}"

            for name, expected_status in [
                ("server_configs/region_us/db_config.json", "archived"),
                ("server_configs/region_us/web_config.json", "active"),
                ("server_configs/region_eu/app1/legacy_cfg.json", "archived"),
            ]:
                stream = tar.extractfile(by_name[name])
                assert stream is not None, f"Could not read archived file: {name}"
                archived_json = json.loads(stream.read().decode("utf-8"))
                assert archived_json.get("status") == expected_status, (
                    f"Archived content for {name} does not contain the expected status"
                )
    except (tarfile.TarError, OSError) as e:
        pytest.fail(f"Failed to read gzipped incremental archive: {e}")


def _uses_python_json_parser(source):
    try:
        tree = ast.parse(source)
    except SyntaxError:
        return False

    module_aliases = set()
    function_aliases = set()
    decoder_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "json":
                    module_aliases.add(alias.asname or "json")
        elif isinstance(node, ast.ImportFrom) and node.module == "json":
            for alias in node.names:
                local_name = alias.asname or alias.name
                if alias.name in ("load", "loads"):
                    function_aliases.add(local_name)
                elif alias.name == "JSONDecoder":
                    decoder_aliases.add(local_name)

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Name) and func.id in function_aliases:
            return True
        if isinstance(func, ast.Attribute):
            if isinstance(func.value, ast.Name) and func.value.id in module_aliases:
                if func.attr in ("load", "loads"):
                    return True
            if func.attr in ("decode", "raw_decode") and isinstance(func.value, ast.Call):
                constructor = func.value.func
                if isinstance(constructor, ast.Name) and constructor.id in decoder_aliases:
                    return True
                if isinstance(constructor, ast.Attribute) and isinstance(constructor.value, ast.Name):
                    if constructor.value.id in module_aliases and constructor.attr == "JSONDecoder":
                        return True
    return False


def _python_script_candidates():
    candidates = []
    ignored = {"incremental_backup.tar.gz", "full_backup.tar.gz", "backup.snar"}
    for root, dirs, files in os.walk("/home/user"):
        dirs[:] = [d for d in dirs if d not in {".cache", "__pycache__", ".local"}]
        for filename in files:
            if filename in ignored:
                continue
            path = os.path.join(root, filename)
            try:
                if not os.path.isfile(path) or os.path.getsize(path) > 1024 * 1024:
                    continue
                with open(path, "rb") as f:
                    first_line = f.readline(256)
                if filename.endswith(".py") or (first_line.startswith(b"#!") and b"python" in first_line.lower()):
                    with open(path, "r", encoding="utf-8") as f:
                        source = f.read()
                    if _uses_python_json_parser(source):
                        candidates.append(path)
            except (OSError, UnicodeError):
                continue
    return sorted(candidates)


def test_z_python_script_parses_and_transforms_discovered_json():
    candidates = _python_script_candidates()
    assert candidates, "No Python script using Python's JSON parser was found under /home/user"

    token = uuid.uuid4().hex
    fixture_dir = f"/home/user/server_configs/.verify_{token}"
    target_path = os.path.join(fixture_dir, f"target_{token}.json")
    nested_path = os.path.join(fixture_dir, f"nested_{token}.json")
    active_path = os.path.join(fixture_dir, f"active_{token}.json")

    errors = []
    try:
        for script in candidates:
            shutil.rmtree(fixture_dir, ignore_errors=True)
            os.makedirs(fixture_dir)
            with open(target_path, "w") as f:
                json.dump({"marker": token, "status": "deprecated", "value": 17}, f, indent=2)
            with open(nested_path, "w") as f:
                json.dump({"marker": token, "status": "active", "nested": {"status": "deprecated"}}, f, indent=2)
            with open(active_path, "w") as f:
                json.dump({"marker": token, "status": "active"}, f, indent=2)

            try:
                result = subprocess.run(
                    [sys.executable, script],
                    cwd="/home/user",
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=30,
                )
            except (OSError, subprocess.TimeoutExpired) as e:
                errors.append(f"{script}: {e}")
                continue

            try:
                with open(target_path) as f:
                    target = json.load(f)
                with open(nested_path) as f:
                    nested = json.load(f)
                with open(active_path) as f:
                    active = json.load(f)
            except (OSError, json.JSONDecodeError) as e:
                errors.append(f"{script}: invalid fixture output: {e}")
                continue

            if (
                result.returncode == 0
                and target.get("status") == "archived"
                and target.get("marker") == token
                and nested.get("status") == "active"
                and nested.get("nested", {}).get("status") == "deprecated"
                and active.get("status") == "active"
            ):
                return

            errors.append(
                f"{script}: exit={result.returncode}, target={target}, nested={nested}, active={active}, stderr={result.stderr[-300:]}"
            )

        pytest.fail("No submitted Python script correctly handled discovered root-level JSON statuses. " + " | ".join(errors))
    finally:
        shutil.rmtree(fixture_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
