#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import importlib.util
import json
import os
import runpy
import subprocess
import sys
import uuid

import pytest

WORKSPACE_DIR = "/home/user/workspace"
REDACTOR_FILE = os.path.join(WORKSPACE_DIR, "redactor.py")
SCHEMA_PB2_FILE = os.path.join(WORKSPACE_DIR, "schema_pb2.py")
REDACTED_FILE = os.path.join(WORKSPACE_DIR, "redacted.jsonl")
SUMMARY_FILE = os.path.join(WORKSPACE_DIR, "summary.json")
TOKENS_FILE = os.path.join(WORKSPACE_DIR, "tokens.txt")
PAYLOADS_FILE = os.path.join(WORKSPACE_DIR, "payloads.jsonl")


def test_protobuf_compiled():
    assert os.path.isfile(SCHEMA_PB2_FILE), f"Protobuf compiled file missing: {SCHEMA_PB2_FILE}"

    spec = importlib.util.spec_from_file_location("verified_schema_pb2", SCHEMA_PB2_FILE)
    assert spec is not None and spec.loader is not None, "Unable to load schema_pb2.py"
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    message = module.DESCRIPTOR.message_types_by_name.get("TransactionLog")
    assert message is not None, "TransactionLog descriptor missing from schema_pb2.py"
    expected = {
        "id": 9,
        "user_agent": 9,
        "request_payload": 9,
        "status_code": 5,
        "response_payload": 9,
    }
    assert {field.name: field.type for field in message.fields} == expected, \
        "schema_pb2.py does not match the provided TransactionLog schema"


def test_redactor_script_exists_and_valid():
    assert os.path.isfile(REDACTOR_FILE), f"Redactor script missing: {REDACTOR_FILE}"

    with open(REDACTOR_FILE, "r", encoding="utf-8") as f:
        source = f.read()

    try:
        tree = ast.parse(source)
    except SyntaxError as e:
        pytest.fail(f"Syntax error in {REDACTOR_FILE}: {e}")

    trie_class_found = False
    methods_found = set()
    redact_node = None

    for node in tree.body:
        if isinstance(node, ast.ClassDef) and node.name == "TokenTrie":
            trie_class_found = True
            for item in node.body:
                if isinstance(item, ast.FunctionDef):
                    methods_found.add(item.name)
                    if item.name == "redact":
                        redact_node = item

    assert trie_class_found, "Class 'TokenTrie' not found in redactor.py"
    assert "add_token" in methods_found, "Method 'add_token' not found in TokenTrie class"
    assert "redact" in methods_found, "Method 'redact' not found in TokenTrie class"

    replace_calls = [
        node for node in ast.walk(redact_node)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "replace"
    ]
    assert not replace_calls, "TokenTrie.redact must use Trie search logic, not str.replace"


def test_summary_json():
    assert os.path.isfile(SUMMARY_FILE), f"Summary file missing: {SUMMARY_FILE}"
    with open(SUMMARY_FILE, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON in {SUMMARY_FILE}")

    assert "total_redactions" in data, "Key 'total_redactions' missing in summary.json"
    assert data["total_redactions"] == 6, f"Expected 6 total redactions, got {data['total_redactions']}"


def test_redacted_jsonl():
    assert os.path.isfile(REDACTED_FILE), f"Redacted file missing: {REDACTED_FILE}"

    expected_lines = [
        {"id": "1", "user_agent": "Mozilla [REDACTED] client", "request_payload": "login [REDACTED]", "status_code": 200, "response_payload": "ok"},
        {"id": "2", "user_agent": "curl/7.68.0", "request_payload": "query data", "status_code": 403, "response_payload": "Missing [REDACTED] or [REDACTED]"},
        {"id": "3", "user_agent": "PostmanRuntime/7.28", "request_payload": "auth [REDACTED] and [REDACTED]", "status_code": 200, "response_payload": "success"}
    ]

    with open(REDACTED_FILE, "r", encoding="utf-8") as f:
        lines = f.read().strip().split('\n')

    assert len(lines) == 3, f"Expected 3 lines in redacted.jsonl, got {len(lines)}"

    for i, line in enumerate(lines):
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            pytest.fail(f"Invalid JSON on line {i+1} of {REDACTED_FILE}")

        assert data == expected_lines[i], f"Mismatch on line {i+1} of {REDACTED_FILE}. Expected {expected_lines[i]}, got {data}"


def _normalize_redact_result(result):
    if isinstance(result, tuple):
        assert result, "TokenTrie.redact returned an empty tuple"
        return result[0]
    return result


def test_z_dynamic_execution_and_trie_behavior():
    paths = [TOKENS_FILE, PAYLOADS_FILE, REDACTED_FILE, SUMMARY_FILE]
    backups = {}
    for path in paths:
        backups[path] = open(path, "rb").read() if os.path.exists(path) else None

    token_a = "audit-a-" + uuid.uuid4().hex
    token_b = "audit-b-" + uuid.uuid4().hex
    dynamic_payloads = [
        {
            "id": "row-" + token_a,
            "user_agent": token_b + "/" + token_a,
            "request_payload": "before " + token_a + " after",
            "status_code": 207,
            "response_payload": "reply " + token_b,
        },
        {
            "id": "plain-id",
            "user_agent": "plain-agent",
            "request_payload": "plain-request",
            "status_code": 418,
            "response_payload": "plain-response",
        },
    ]
    expected_payloads = [
        {
            "id": "row-[REDACTED]",
            "user_agent": "[REDACTED]/[REDACTED]",
            "request_payload": "before [REDACTED] after",
            "status_code": 207,
            "response_payload": "reply [REDACTED]",
        },
        dynamic_payloads[1],
    ]

    try:
        with open(TOKENS_FILE, "w", encoding="utf-8") as f:
            f.write(token_a + "\n" + token_b + "\n")
        with open(PAYLOADS_FILE, "w", encoding="utf-8") as f:
            for payload in dynamic_payloads:
                f.write(json.dumps(payload) + "\n")

        for output in (REDACTED_FILE, SUMMARY_FILE):
            if os.path.exists(output):
                os.remove(output)

        completed = subprocess.run(
            [sys.executable, REDACTOR_FILE],
            cwd=WORKSPACE_DIR,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert completed.returncode == 0, \
            f"redactor.py failed on dynamic input:\n{completed.stdout}\n{completed.stderr}"
        assert os.path.isfile(REDACTED_FILE), "redactor.py did not generate redacted.jsonl"
        assert os.path.isfile(SUMMARY_FILE), "redactor.py did not generate summary.json"

        with open(REDACTED_FILE, "r", encoding="utf-8") as f:
            generated_lines = [line for line in f.read().splitlines() if line.strip()]
        assert len(generated_lines) == len(expected_payloads)
        generated = [json.loads(line) for line in generated_lines]
        assert generated == expected_payloads, \
            f"redactor.py produced incorrect output for verifier-generated inputs: {generated}"

        with open(SUMMARY_FILE, "r", encoding="utf-8") as f:
            summary = json.load(f)
        assert summary == {"total_redactions": 5}, \
            f"Incorrect dynamic redaction summary: {summary}"

        if WORKSPACE_DIR not in sys.path:
            sys.path.insert(0, WORKSPACE_DIR)
        namespace = runpy.run_path(REDACTOR_FILE, run_name="redactor_api_test")
        trie_class = namespace.get("TokenTrie")
        assert isinstance(trie_class, type), "TokenTrie is not an executable class"

        direct_a = "direct-a-" + uuid.uuid4().hex
        direct_b = "direct-b-" + uuid.uuid4().hex
        trie = trie_class()
        untouched = _normalize_redact_result(trie.redact("x" + direct_a + "y"))
        assert untouched == "x" + direct_a + "y", "A fresh TokenTrie redacted an unknown token"
        trie.add_token(direct_a)
        trie.add_token(direct_b)
        actual = _normalize_redact_result(
            trie.redact("pre" + direct_a + "mid" + direct_b + direct_a + "post")
        )
        assert actual == "pre[REDACTED]mid[REDACTED][REDACTED]post", \
            f"TokenTrie methods do not perform required redaction: {actual!r}"
    finally:
        for path, content in backups.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
