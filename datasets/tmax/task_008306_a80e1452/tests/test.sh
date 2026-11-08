#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile

import pytest

SCRIPT = Path("/home/user/etl_pipeline.py")
RAW = Path("/home/user/data/raw_events.jsonl")
TEMPLATE = Path("/home/user/data/template.md.j2")
REPORT = Path("/home/user/output/report.md")


def run_pipeline(env=None):
    return subprocess.run(
        ["python3", str(SCRIPT)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        env=env,
    )


def test_etl_script_exists():
    script_path = "/home/user/etl_pipeline.py"
    assert os.path.isfile(script_path), f"ETL script not found at {script_path}"


def test_report_exists():
    report_path = "/home/user/output/report.md"
    assert os.path.isfile(report_path), f"Output report not found at {report_path}"


def test_report_content():
    report_path = "/home/user/output/report.md"
    with open(report_path, "r", encoding="utf-8") as f:
        content = f.read()

    # The template header should be present
    assert "# Daily Event Report" in content, "Report is missing the required header."
    assert "We processed the following unique events today:" in content, "Report is missing the introductory text."

    # Expected cleaned and deduplicated messages in order
    expected_messages = [
        "System started successfully ✓",
        "Error encountered: ? unknown module",
        "User login: admin",
        "Cache flushed",
        "Warning: ? invalid token",
        "User logout: admin"
    ]

    for msg in expected_messages:
        assert f"* {msg}" in content, f"Expected message '{msg}' not found in the report."

    # Check for duplicates or unprocessed invalid sequences
    assert "\\uZZZZ" not in content, "Unprocessed invalid unicode sequence \\uZZZZ found in report."
    assert "\\uG123" not in content, "Unprocessed invalid unicode sequence \\uG123 found in report."

    # Check that there are exactly 6 items in the list to ensure deduplication worked
    list_items = [line for line in content.splitlines() if line.strip().startswith("* ")]
    assert len(list_items) >= 5, "Validation checkpoint failed: There should be at least 5 unique records."

    # Ensure no duplicates in the report list
    unique_items = set(list_items)
    assert len(list_items) == len(unique_items), "Duplicate messages found in the final report."
    assert len(list_items) == 6, f"Expected exactly 6 deduplicated messages, found {len(list_items)}."


def test_required_implementation_constructs_are_present():
    source = SCRIPT.read_text(encoding="utf-8")
    tree = ast.parse(source)
    imported_modules = set()
    call_names = set()
    has_value_error_raise = False
    has_function = False

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported_modules.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported_modules.add(node.module.split(".")[0])
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            has_function = True
        elif isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                call_names.add(node.func.id)
            elif isinstance(node.func, ast.Attribute):
                call_names.add(node.func.attr)
        elif isinstance(node, ast.Raise) and isinstance(node.exc, ast.Call):
            if isinstance(node.exc.func, ast.Name) and node.exc.func.id == "ValueError":
                has_value_error_raise = True

    assert "re" in imported_modules, "The pipeline must use Python regular expressions for cleaning."
    assert call_names.intersection({"compile", "sub", "search", "findall", "finditer"}), "No regex operation was found."
    assert "hashlib" in imported_modules and "sha256" in source.lower(), "SHA-256 hashing was not implemented."
    assert "jinja2" in imported_modules, "The pipeline must import and use jinja2."
    assert call_names.intersection({"Template", "Environment", "FileSystemLoader", "get_template", "from_string"}), "No Jinja2 template operation was found."
    assert has_function and has_value_error_raise, "A validation function that raises ValueError is required."


def test_pipeline_on_unseen_data_and_validation_failure():
    raw_backup = RAW.read_bytes()
    template_backup = TEMPLATE.read_bytes()
    report_backup = REPORT.read_bytes() if REPORT.exists() else None
    nonce = secrets.token_hex(8)

    messages = [
        f"alpha {nonce}",
        f"broken ? {nonce}",
        f"unicode ☺ {nonce}",
        f"delta {nonce}",
        f"echo {nonce}",
        f"foxtrot {nonce}",
    ]
    lines = [
        json.dumps({"id": 1, "message": messages[0]}, ensure_ascii=False),
        f'{{"id": 2, "message": "broken \\uZ12? {nonce}"}}',
        f'{{"id": 3, "message": "unicode \\u263A {nonce}"}}',
        json.dumps({"id": 4, "message": messages[0]}, ensure_ascii=False),
        json.dumps({"id": 5, "message": messages[3]}, ensure_ascii=False),
        json.dumps({"id": 6, "message": messages[4]}, ensure_ascii=False),
        json.dumps({"id": 7, "message": messages[5]}, ensure_ascii=False),
    ]
    dynamic_template = (
        f"DYNAMIC-{nonce}\n"
        "COUNT={{ messages|length }}\n"
        "{% for msg in messages %}{{ loop.index }}::{{ msg }}\n{% endfor %}"
    )
    expected = (
        f"DYNAMIC-{nonce}\nCOUNT=6\n"
        + "".join(f"{index}::{message}\n" for index, message in enumerate(messages, 1))
    )

    try:
        RAW.write_text("\n".join(lines) + "\n", encoding="utf-8")
        TEMPLATE.write_text(dynamic_template, encoding="utf-8")
        if REPORT.exists():
            REPORT.unlink()

        with tempfile.TemporaryDirectory() as td:
            trace = Path(td) / "sha_trace"
            Path(td, "sitecustomize.py").write_text(
                "import hashlib, os\n"
                "_sha256 = hashlib.sha256\n"
                "_new = hashlib.new\n"
                "def _mark():\n"
                "    with open(os.environ['SHA_TRACE'], 'a') as f: f.write('1\\n')\n"
                "def traced_sha256(*args, **kwargs):\n"
                "    _mark()\n"
                "    return _sha256(*args, **kwargs)\n"
                "def traced_new(name, *args, **kwargs):\n"
                "    if str(name).lower().replace('-', '') == 'sha256': _mark()\n"
                "    return _new(name, *args, **kwargs)\n"
                "hashlib.sha256 = traced_sha256\n"
                "hashlib.new = traced_new\n",
                encoding="utf-8",
            )
            env = os.environ.copy()
            env["SHA_TRACE"] = str(trace)
            env["PYTHONPATH"] = td + os.pathsep + env.get("PYTHONPATH", "")
            result = run_pipeline(env)
            assert result.returncode == 0, result.stdout + result.stderr
            assert trace.exists() and trace.read_text().strip(), "The executed pipeline did not compute SHA-256 hashes."

        assert REPORT.is_file(), "The executed pipeline did not create report.md."
        assert REPORT.read_text(encoding="utf-8") == expected, "The pipeline failed on unseen cleaning, ordering, deduplication, or Jinja2 template data."

        too_few = [
            json.dumps({"id": i, "message": f"small-{i}-{nonce}"})
            for i in range(1, 5)
        ]
        RAW.write_text("\n".join(too_few) + "\n", encoding="utf-8")
        result = run_pipeline()
        combined = result.stdout + result.stderr
        assert result.returncode != 0, "The pipeline must fail when fewer than five unique messages remain."
        assert "ValueError" in combined, "The quality gate must raise ValueError on validation failure."
    finally:
        RAW.write_bytes(raw_backup)
        TEMPLATE.write_bytes(template_backup)
        if report_backup is None:
            REPORT.unlink(missing_ok=True)
        else:
            REPORT.write_bytes(report_backup)
        run_pipeline()
TEST_EOF

if python3 /home/user/etl_pipeline.py && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
