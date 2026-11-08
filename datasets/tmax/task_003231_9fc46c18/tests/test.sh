#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import random
import re
import secrets
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/config_filter.py"
CLEAN_CORPUS = "/app/corpora/clean"
EVIL_CORPUS = "/app/corpora/evil"
PARSER_PATH = "/app/legacy_parser"
DELIMITER = b"---END RECORD---"


def get_records(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    if not content:
        return []
    records = content.split('---END RECORD---')
    return [r for r in records if r.strip()]


def is_evil(record):
    match = re.search(r'SetPrivilege:\s*true\s+Timeout:\s*(\d+)', record)
    if match:
        return int(match.group(1)) > 9999
    return False


def split_records_exact(data):
    records = []
    current = bytearray()
    for line in data.splitlines(keepends=True):
        current.extend(line)
        if DELIMITER in line:
            records.append(bytes(current))
            current.clear()
    if current:
        records.append(bytes(current))
    return records


def parser_says_evil(record):
    result = subprocess.run([PARSER_PATH], input=record, capture_output=True)
    assert result.returncode in (0, 42), (
        f"legacy parser returned unexpected status {result.returncode}: {result.stderr!r}"
    )
    return result.returncode == 42


def exact_expected(path):
    with open(path, "rb") as f:
        records = split_records_exact(f.read())
    return b"".join(record for record in records if not parser_says_evil(record))


def assert_streaming_or_mmap_implementation():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT_PATH)

    mmap_names = set()
    mmap_module_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "mmap":
                    mmap_module_names.add(alias.asname or alias.name)
        elif isinstance(node, ast.ImportFrom) and node.module == "mmap":
            for alias in node.names:
                if alias.name == "mmap":
                    mmap_names.add(alias.asname or alias.name)

    mmap_used = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in mmap_names:
            mmap_used = True
        elif (isinstance(node.func, ast.Attribute)
              and node.func.attr == "mmap"
              and isinstance(node.func.value, ast.Name)
              and node.func.value.id in mmap_module_names):
            mmap_used = True

    file_vars = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.With):
            for item in node.items:
                call = item.context_expr
                if (isinstance(call, ast.Call)
                    and ((isinstance(call.func, ast.Name) and call.func.id == "open")
                         or (isinstance(call.func, ast.Attribute) and call.func.attr == "open"))
                    and isinstance(item.optional_vars, ast.Name)):
                    file_vars.add(item.optional_vars.id)
        elif isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            if (isinstance(value, ast.Call)
                and ((isinstance(value.func, ast.Name) and value.func.id == "open")
                     or (isinstance(value.func, ast.Attribute) and value.func.attr == "open"))):
                targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                for target in targets:
                    if isinstance(target, ast.Name):
                        file_vars.add(target.id)

    iterative_file_read = any(
        isinstance(node, (ast.For, ast.AsyncFor))
        and isinstance(node.iter, ast.Name)
        and node.iter.id in file_vars
        for node in ast.walk(tree)
    )

    bounded_read = False
    unbounded_reads = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        method = node.func.attr
        if method in ("read_text", "read_bytes"):
            unbounded_reads.append(method)
        elif method == "read":
            size_arg = node.args[0] if node.args else None
            if size_arg is None:
                for keyword in node.keywords:
                    if keyword.arg in ("size", "n"):
                        size_arg = keyword.value
                        break
            if size_arg is None or (isinstance(size_arg, ast.Constant) and size_arg.value in (-1, None)):
                unbounded_reads.append("read")
            else:
                bounded_read = True
        elif method == "readline":
            bounded_read = True

    assert not unbounded_reads, (
        "Input files must not be loaded wholesale; found unbounded operation(s): "
        + ", ".join(unbounded_reads)
    )
    assert mmap_used or iterative_file_read or bounded_read, (
        "The implementation must actually use mmap, file iteration, readline(), "
        "or bounded chunk reads for log input"
    )


def test_streaming_or_mmap_requirement():
    assert_streaming_or_mmap_implementation()


def test_config_filter_clean_corpus():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    with tempfile.TemporaryDirectory() as out_dir:
        result = subprocess.run(
            ["python3", SCRIPT_PATH, CLEAN_CORPUS, out_dir],
            capture_output=True, text=True
        )
        assert result.returncode == 0, f"Script failed on clean corpus:\n{result.stderr}"

        clean_files = []
        for root, _, files in os.walk(CLEAN_CORPUS):
            for file in files:
                if file.endswith('.log'):
                    clean_files.append(os.path.relpath(os.path.join(root, file), CLEAN_CORPUS))

        modified_clean = []
        for rel_file in clean_files:
            in_file = os.path.join(CLEAN_CORPUS, rel_file)
            out_file = os.path.join(out_dir, rel_file)

            if not os.path.exists(out_file):
                modified_clean.append(f"{rel_file} (missing)")
                continue

            with open(in_file, 'r', encoding='utf-8') as f1, open(out_file, 'r', encoding='utf-8') as f2:
                if f1.read() != f2.read():
                    modified_clean.append(f"{rel_file} (content mismatch)")

        if modified_clean:
            assert False, f"{len(modified_clean)} of {len(clean_files)} clean modified: {', '.join(modified_clean)}"


def test_config_filter_evil_corpus():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    with tempfile.TemporaryDirectory() as out_dir:
        result = subprocess.run(
            ["python3", SCRIPT_PATH, EVIL_CORPUS, out_dir],
            capture_output=True, text=True
        )
        assert result.returncode == 0, f"Script failed on evil corpus:\n{result.stderr}"

        evil_files = []
        for root, _, files in os.walk(EVIL_CORPUS):
            for file in files:
                if file.endswith('.log'):
                    evil_files.append(os.path.relpath(os.path.join(root, file), EVIL_CORPUS))

        bypassed_evil = []
        for rel_file in evil_files:
            in_file = os.path.join(EVIL_CORPUS, rel_file)
            out_file = os.path.join(out_dir, rel_file)

            in_records = get_records(in_file)
            expected_clean_records = [r for r in in_records if not is_evil(r)]

            if not os.path.exists(out_file):
                if expected_clean_records:
                    bypassed_evil.append(f"{rel_file} (missing output but has clean records)")
                continue

            out_records = get_records(out_file)
            evil_in_out = [r for r in out_records if is_evil(r)]
            if evil_in_out:
                bypassed_evil.append(f"{rel_file} ({len(evil_in_out)} evil records bypassed)")
                continue

            if len(out_records) != len(expected_clean_records):
                bypassed_evil.append(f"{rel_file} (clean records count mismatch: expected {len(expected_clean_records)}, got {len(out_records)})")
                continue

            with open(out_file, "rb") as f:
                actual = f.read()
            expected = exact_expected(in_file)
            if actual != expected:
                bypassed_evil.append(f"{rel_file} (retained records were not preserved exactly)")

        if bypassed_evil:
            assert False, f"{len(bypassed_evil)} of {len(evil_files)} evil bypassed or malformed: {', '.join(bypassed_evil)}"


def make_record(host, lines):
    return ("Host: " + host + "\n" + "\n".join(lines) + "\n---END RECORD---\n").encode("utf-8")


def test_generated_nested_corpus_against_legacy_parser():
    token = secrets.token_hex(8)
    high = 10000 + secrets.randbelow(900000)
    low = secrets.randbelow(10000)

    records_a = [
        make_record(f"benign-{token}", ["SetPrivilege: false", f"Timeout: {high}", "Mode: exact-a"]),
        make_record(f"direct-{token}", ["SetPrivilege: true", f"Timeout: {high}", "Mode: remove-a"]),
        make_record(f"stateful-{token}", ["SetPrivilege: true", "Comment: directive-between", f"Timeout: {high}"]),
        make_record(f"low-{token}", ["SetPrivilege: true", f"Timeout: {low}", "Mode: exact-b"]),
    ]
    records_b = [
        make_record(f"order-{token}", [f"Timeout: {high}", "SetPrivilege: true", "Comment: no-following-timeout"]),
        make_record(f"second-{token}", ["SetPrivilege: true", "Other: untouched", f"Timeout: {high + 1}"]),
        make_record(f"plain-{token}", ["SetPrivilege: false", "Timeout: 17", f"Nonce: {token}"]),
    ]
    random.SystemRandom().shuffle(records_a)
    random.SystemRandom().shuffle(records_b)

    with tempfile.TemporaryDirectory() as input_dir, tempfile.TemporaryDirectory() as output_dir:
        nested_a = os.path.join(input_dir, f"level-{token}", "deeper")
        nested_b = os.path.join(input_dir, "other", f"branch-{token}")
        os.makedirs(nested_a)
        os.makedirs(nested_b)
        paths = {
            os.path.join(nested_a, f"changes-{token}.log"): b"".join(records_a),
            os.path.join(nested_b, f"audit-{token}.log"): b"".join(records_b),
        }
        for path, data in paths.items():
            with open(path, "wb") as f:
                f.write(data)
        with open(os.path.join(input_dir, f"ignore-{token}.txt"), "wb") as f:
            f.write(b"not a log file\n")

        result = subprocess.run(
            ["python3", SCRIPT_PATH, input_dir, output_dir],
            capture_output=True, text=True, timeout=30
        )
        assert result.returncode == 0, f"Script failed on generated corpus:\n{result.stderr}"

        for input_path in paths:
            rel = os.path.relpath(input_path, input_dir)
            output_path = os.path.join(output_dir, rel)
            assert os.path.isfile(output_path), f"Missing nested output file: {rel}"
            expected = exact_expected(input_path)
            with open(output_path, "rb") as f:
                actual = f.read()
            assert actual == expected, f"Incorrect filtering or formatting for generated file {rel}"


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
