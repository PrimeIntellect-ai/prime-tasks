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
from pathlib import Path
from urllib.parse import unquote, urlparse

import pytest

PROJECT = Path("/home/user/log_processor")
OUTPUT = Path("/home/user/migrated_output.jsonl")
RAW = Path("/home/user/raw_data.log")
PIPELINE = Path("/home/user/run_pipeline.py")


def run(command, *, cwd=None, env=None):
    result = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert result.returncode == 0, result.stdout
    return result.stdout


def read_jsonl(path):
    records = []
    with open(path, "r", encoding="utf-8") as handle:
        for line_num, line in enumerate(handle, 1):
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError as exc:
                pytest.fail(f"Line {line_num} in {path} is not valid JSON: {exc}")
    return records


def test_migrated_output_exists_and_correct():
    assert OUTPUT.is_file(), f"Output file missing: {OUTPUT}"

    expected_records = [
        {"transaction_id": 1001, "schema_version": 2, "properties": {"status": "success", "region": "us-east-1"}},
        {"transaction_id": 1002, "schema_version": 2, "properties": {"status": "failure", "error_code": "500", "retries": "3"}},
        {"transaction_id": 1003, "schema_version": 2, "properties": {}},
    ]
    actual_records = read_jsonl(OUTPUT)

    assert len(actual_records) == len(expected_records), (
        f"Expected {len(expected_records)} records, but found {len(actual_records)} in {OUTPUT}"
    )
    for i, (actual, expected) in enumerate(zip(actual_records, expected_records)):
        assert actual == expected, f"Record {i+1} mismatch.\nExpected: {expected}\nActual: {actual}"


def test_setup_py_conditional_compilation():
    setup_path = PROJECT / "setup.py"
    assert setup_path.is_file(), f"setup.py missing: {setup_path}"
    content = setup_path.read_text(encoding="utf-8")
    assert "ENABLE_C_EXT" in content, "setup.py does not check for ENABLE_C_EXT environment variable"

    # With the C source deliberately absent, editable installation must still
    # succeed both when the variable is absent and when it is exactly 0.
    for setting in (None, "0"):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            project_copy = root / "project"
            shutil.copytree(PROJECT, project_copy)
            (project_copy / "src/log_processor/_fast_ext.c").unlink()
            shutil.rmtree(project_copy / "build", ignore_errors=True)
            for artifact in (project_copy / "src/log_processor").glob("_fast_ext*.so"):
                artifact.unlink()

            env = os.environ.copy()
            if setting is None:
                env.pop("ENABLE_C_EXT", None)
            else:
                env["ENABLE_C_EXT"] = setting
            run(
                [
                    sys.executable,
                    "-m",
                    "pip",
                    "install",
                    "--disable-pip-version-check",
                    "--no-deps",
                    "--no-build-isolation",
                    "--ignore-installed",
                    "--prefix",
                    str(root / "prefix"),
                    "-e",
                    str(project_copy),
                ],
                env=env,
            )

    # With ENABLE_C_EXT=1, setup.py must really build the named extension.
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        project_copy = root / "project"
        build_lib = root / "lib"
        build_temp = root / "temp"
        shutil.copytree(PROJECT, project_copy)
        shutil.rmtree(project_copy / "build", ignore_errors=True)
        for artifact in (project_copy / "src/log_processor").glob("_fast_ext*.so"):
            artifact.unlink()

        env = os.environ.copy()
        env["ENABLE_C_EXT"] = "1"
        run(
            [
                sys.executable,
                "setup.py",
                "build_ext",
                "--force",
                "--build-lib",
                str(build_lib),
                "--build-temp",
                str(build_temp),
            ],
            cwd=project_copy,
            env=env,
        )
        extensions = list((build_lib / "log_processor").glob("_fast_ext*.so"))
        assert extensions, "ENABLE_C_EXT=1 did not build log_processor._fast_ext"
        import_env = os.environ.copy()
        import_env["PYTHONPATH"] = str(build_lib)
        run(
            [sys.executable, "-c", "import log_processor._fast_ext as e; assert e.is_fast() is True"],
            cwd=root,
            env=import_env,
        )


def test_package_is_installed_editably_from_project():
    code = r'''
import importlib.metadata
import json
from pathlib import Path
from urllib.parse import unquote, urlparse
import log_processor
import log_processor.parser
import log_processor.migrator

project = Path("/home/user/log_processor").resolve()
parser_path = Path(log_processor.parser.__file__).resolve()
migrator_path = Path(log_processor.migrator.__file__).resolve()
assert project in parser_path.parents, parser_path
assert project in migrator_path.parents, migrator_path

dist = importlib.metadata.distribution("log_processor")
direct = dist.read_text("direct_url.json")
assert direct, "log_processor lacks editable-install metadata"
info = json.loads(direct)
assert info.get("dir_info", {}).get("editable") is True, info
installed_from = Path(unquote(urlparse(info["url"]).path)).resolve()
assert installed_from == project, (installed_from, project)
'''
    run([sys.executable, "-c", code], cwd="/tmp")


def test_parser_and_migrator_on_unseen_input():
    from log_processor.migrator import migrate_schema
    from log_processor.parser import parse_logs

    token = secrets.token_hex(6)
    tx1 = secrets.randbelow(800000) + 100000
    tx2 = tx1 + 1
    key1 = "field_" + token
    value1 = "value_" + secrets.token_hex(5)
    key2 = "other_" + secrets.token_hex(4)
    value2 = "data_" + secrets.token_hex(5)

    text = "\n".join([
        "ATTR outside=ignored",
        "BEGIN not-a-transaction",
        f"BEGIN tx={tx1}",
        f"ATTR {key1}={value1}",
        "THIS LINE IS IGNORED",
        f"ATTR {key2}={value2}",
        "END",
        "random outside text",
        f"BEGIN tx={tx2}",
        "END",
        "ATTR also_outside=ignored",
        "",
    ])

    with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as handle:
        handle.write(text)
        path = handle.name
    try:
        parsed = parse_logs(path)
    finally:
        os.unlink(path)

    expected_parsed = [
        {"tx": str(tx1), key1: value1, key2: value2},
        {"tx": str(tx2)},
    ]
    assert parsed == expected_parsed

    expected_migrated = [
        {"transaction_id": tx1, "schema_version": 2, "properties": {key1: value1, key2: value2}},
        {"transaction_id": tx2, "schema_version": 2, "properties": {}},
    ]
    assert migrate_schema(parsed) == expected_migrated

    arbitrary = [{"tx": str(tx2 + 10), "alpha": token, "count": "7"}]
    assert migrate_schema(arbitrary) == [
        {"transaction_id": tx2 + 10, "schema_version": 2, "properties": {"alpha": token, "count": "7"}}
    ]


def test_run_pipeline_exists_and_processes_unseen_log():
    assert PIPELINE.is_file(), f"Pipeline script missing: {PIPELINE}"

    tx1 = secrets.randbelow(8000000) + 1000000
    tx2 = tx1 + 7
    key = "dynamic_" + secrets.token_hex(5)
    value = "payload_" + secrets.token_hex(8)
    raw_contents = "\n".join([
        "noise before",
        f"BEGIN tx={tx1}",
        f"ATTR {key}={value}",
        "INVALID INSIDE BLOCK",
        "END",
        "noise between",
        f"BEGIN tx={tx2}",
        "END",
        "noise after",
        "",
    ])
    expected = [
        {"transaction_id": tx1, "schema_version": 2, "properties": {key: value}},
        {"transaction_id": tx2, "schema_version": 2, "properties": {}},
    ]

    raw_backup = RAW.read_bytes() if RAW.exists() else None
    output_backup = OUTPUT.read_bytes() if OUTPUT.exists() else None
    try:
        RAW.write_text(raw_contents, encoding="utf-8")
        if OUTPUT.exists():
            OUTPUT.unlink()
        run([sys.executable, str(PIPELINE)], cwd="/home/user")
        assert OUTPUT.is_file(), "run_pipeline.py did not create migrated_output.jsonl"
        assert read_jsonl(OUTPUT) == expected
    finally:
        if raw_backup is None:
            RAW.unlink(missing_ok=True)
        else:
            RAW.write_bytes(raw_backup)
        if output_backup is None:
            OUTPUT.unlink(missing_ok=True)
        else:
            OUTPUT.write_bytes(output_backup)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
