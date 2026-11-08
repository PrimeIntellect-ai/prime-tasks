#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import stat
import subprocess
import sys


def evaluate_expression(expr):
    # Safe evaluation of simple math expressions
    try:
        return eval(expr, {"__builtins__": None}, {})
    except Exception:
        return None


def test_pipeline_log_content():
    expressions_file = '/home/user/data/expressions.txt'
    log_file = '/home/user/pipeline.log'

    assert os.path.exists(expressions_file), f"{expressions_file} is missing"
    assert os.path.exists(log_file), f"{log_file} is missing"

    with open(expressions_file, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    seen_hashes = set()
    duplicates = 0
    total_lines = len(lines)

    for expr in lines:
        val = evaluate_expression(expr)
        if val is not None:
            formatted_val = f"{val:.4f}"
            h = hashlib.md5(formatted_val.encode('utf-8')).hexdigest()
            if h in seen_hashes:
                duplicates += 1
            else:
                seen_hashes.add(h)

    expected_log = f"INFO: Processed {total_lines} lines, found {duplicates} duplicates."

    with open(log_file, 'r') as f:
        log_content = f.read().strip()

    assert expected_log in log_content, f"Expected '{expected_log}' in {log_file}, but got: {log_content}"


def test_report_content():
    expressions_file = '/home/user/data/expressions.txt'
    template_file = '/home/user/template.md'
    report_file = '/home/user/report.md'

    assert os.path.exists(expressions_file), f"{expressions_file} is missing"
    assert os.path.exists(template_file), f"{template_file} is missing"
    assert os.path.exists(report_file), f"{report_file} is missing"

    with open(expressions_file, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    seen_hashes = set()
    unique_expressions = []

    for expr in lines:
        val = evaluate_expression(expr)
        if val is not None:
            formatted_val = f"{val:.4f}"
            h = hashlib.md5(formatted_val.encode('utf-8')).hexdigest()
            if h not in seen_hashes:
                seen_hashes.add(h)
                unique_expressions.append(f"{expr} = {val:.1f}")

    with open(template_file, 'r') as f:
        template = f.read()

    expected_report = template.replace('{{UNIQUE_COUNT}}', str(len(unique_expressions)))
    expected_report = expected_report.replace('{{EXPRESSIONS_LIST}}', '\n'.join(unique_expressions))

    with open(report_file, 'r') as f:
        actual_report = f.read().strip()

    assert actual_report == expected_report.strip(), f"Content of {report_file} does not match the expected output based on the template."


def test_script_executes_on_unseen_input():
    script = '/home/user/process_math.py'
    assert os.path.exists(script), f"{script} is missing"
    assert stat.S_ISREG(os.lstat(script).st_mode), f"{script} is not a regular file"

    expressions_file = '/home/user/data/expressions.txt'
    template_file = '/home/user/template.md'
    report_file = '/home/user/report.md'
    log_file = '/home/user/pipeline.log'
    state_paths = [expressions_file, template_file, report_file, log_file]
    backups = {}
    for path in state_paths:
        backups[path] = open(path, 'rb').read() if os.path.exists(path) else None

    base = secrets.randbelow(9000) + 1000
    marker = secrets.token_hex(12)
    expressions = [
        f"{base} + 0",
        f"{base * 2} / 2",
        f"{base + 7} - 0",
        f"({base + 7}) * 1",
        f"{base} / 8",
        f"{base * 3} / 3",
        "2 ** 5",
    ]
    template = (
        f"# Verification {marker}\n"
        "Unique={{UNIQUE_COUNT}}\n"
        "BEGIN\n{{EXPRESSIONS_LIST}}\nEND\n"
    )

    seen_hashes = set()
    unique_expressions = []
    duplicates = 0
    for expr in expressions:
        val = evaluate_expression(expr)
        assert val is not None
        formatted_val = f"{val:.4f}"
        digest = hashlib.md5(formatted_val.encode('utf-8')).hexdigest()
        if digest in seen_hashes:
            duplicates += 1
        else:
            seen_hashes.add(digest)
            unique_expressions.append(f"{expr} = {val:.1f}")

    expected_log = f"INFO: Processed {len(expressions)} lines, found {duplicates} duplicates."
    expected_report = template.replace('{{UNIQUE_COUNT}}', str(len(unique_expressions)))
    expected_report = expected_report.replace('{{EXPRESSIONS_LIST}}', '\n'.join(unique_expressions))

    try:
        with open(expressions_file, 'w') as f:
            f.write('\n'.join(expressions) + '\n')
        with open(template_file, 'w') as f:
            f.write(template)
        for path in (report_file, log_file):
            if os.path.exists(path):
                os.remove(path)

        result = subprocess.run(
            [sys.executable, script],
            cwd='/home/user',
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Executing {script} failed with exit code {result.returncode}. "
            f"stdout: {result.stdout} stderr: {result.stderr}"
        )
        assert os.path.exists(report_file), f"{script} did not create {report_file}"
        assert os.path.exists(log_file), f"{script} did not create {log_file}"

        with open(report_file, 'r') as f:
            actual_report = f.read().strip()
        with open(log_file, 'r') as f:
            actual_log = f.read().strip()

        assert actual_report == expected_report.strip(), "Script produced an incorrect report for unseen input"
        assert actual_log == expected_log, "Script produced an incorrect log for unseen input"
    finally:
        for path, content in backups.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, 'wb') as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
