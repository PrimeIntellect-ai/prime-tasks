#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import re
import secrets
import shutil
import stat
import subprocess
import tempfile

import pytest


def test_interpreter_patched():
    path = "/home/user/interpreter.sh"
    assert os.path.isfile(path), f"Interpreter script is missing at {path}"
    with open(path, 'r') as f:
        content = f.read()
    assert "set -f" in content, "The interpreter script was not patched to fix globbing (missing 'set -f')."


def test_test_runner_exists_and_executable():
    path = "/home/user/test_runner.sh"
    assert os.path.isfile(path), f"Test runner script is missing at {path}"
    assert os.access(path, os.X_OK), f"Test runner script at {path} is not executable."


def test_test_data_directory_and_files():
    dir_path = "/home/user/test_data"
    assert os.path.isdir(dir_path), f"Test data directory is missing at {dir_path}"

    expected_files = {
        "test_1.txt": "10 5 +",
        "test_2.txt": "20 4 /",
        "test_3.txt": "3 4 * 2 +",
        "test_4.txt": "15 5 - 2 *",
        "test_5.txt": "100 10 / 5 *",
        "test_6.txt": "50 25 - 5 /",
        "test_7.txt": "7 8 * 10 -"
    }

    for filename, expected_content in expected_files.items():
        file_path = os.path.join(dir_path, filename)
        assert os.path.isfile(file_path), f"Test fixture file missing: {file_path}"
        with open(file_path, 'r') as f:
            content = f.read().strip()
        assert content == expected_content, f"Content of {file_path} is incorrect. Expected '{expected_content}', got '{content}'."


def test_test_report_log():
    path = "/home/user/test_report.log"
    assert os.path.isfile(path), f"Test report log is missing at {path}"

    expected_lines = [
        "Test 1: 15",
        "Test 2: 5",
        "Test 3: 14",
        "Test 4: 20",
        "Test 5: 50",
        "Test 6: 5",
        "Test 7: 46"
    ]

    with open(path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_lines, f"Test report log content is incorrect or not properly sorted. Expected: {expected_lines}, Got: {lines}"


def test_interpreter_really_disables_globbing(tmp_path):
    # A literal '*' must remain an RPN operator even in a directory containing files.
    (tmp_path / "alpha").write_text("x")
    (tmp_path / "beta").write_text("x")
    result = subprocess.run(
        ["/home/user/interpreter.sh", "3 4 * 2 +"],
        cwd=tmp_path,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "14", f"Interpreter failed the globbing case: {result.stdout!r} {result.stderr!r}"


def eval_rpn(expression):
    stack = []
    for token in expression.split():
        if re.fullmatch(r"-?[0-9]+", token):
            stack.append(int(token))
            continue
        b = stack.pop()
        a = stack.pop()
        if token == "+":
            stack.append(a + b)
        elif token == "-":
            stack.append(a - b)
        elif token == "*":
            stack.append(a * b)
        elif token == "/":
            stack.append(int(a / b))
        else:
            raise AssertionError(f"Unexpected operator {token}")
    assert len(stack) == 1
    return stack[0]


def test_runner_executes_dynamic_fixtures_concurrently_and_waits():
    runner = "/home/user/test_runner.sh"
    fixtures_path = "/home/user/fixtures.csv"
    interpreter_path = "/home/user/interpreter.sh"
    data_path = "/home/user/test_data"
    report_path = "/home/user/test_report.log"

    with open(runner, "r") as f:
        runner_source = f.read()
    syntax = subprocess.run(["bash", "-n", runner], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert syntax.returncode == 0, f"test_runner.sh is not valid Bash: {syntax.stderr}"
    assert re.search(r"(?<!&)&(?!&)", runner_source), "test_runner.sh does not contain a Bash background-job '&' operator"

    with tempfile.TemporaryDirectory(prefix="runner_verify_") as td:
        original_fixtures = open(fixtures_path, "rb").read()
        original_fixtures_mode = stat.S_IMODE(os.stat(fixtures_path).st_mode)
        original_interpreter = open(interpreter_path, "rb").read()
        original_interpreter_mode = stat.S_IMODE(os.stat(interpreter_path).st_mode)
        original_report = open(report_path, "rb").read() if os.path.exists(report_path) else None
        original_report_mode = stat.S_IMODE(os.stat(report_path).st_mode) if os.path.exists(report_path) else None
        saved_data = os.path.join(td, "saved_test_data")
        if os.path.isdir(data_path):
            shutil.copytree(data_path, saved_data)

        real_interpreter = os.path.join(td, "real_interpreter.sh")
        with open(real_interpreter, "wb") as f:
            f.write(original_interpreter)
        os.chmod(real_interpreter, original_interpreter_mode)

        event_log = os.path.join(td, "events.log")
        wait_log = os.path.join(td, "wait.log")
        bash_env = os.path.join(td, "bash_env.sh")

        offset = secrets.randbelow(5000) + 100
        ids = [offset + n for n in (71, 3, 408, 29, 150, 9)]
        a = secrets.randbelow(30) + 11
        b = secrets.randbelow(8) + 2
        expressions = [
            f"{a} {b} +",
            f"{a + 5} {b} *",
            f"{a} {b} * 7 +",
            f"{(a + 2) * b} {b} /",
            f"{a + 40} {b} - 3 *",
            f"{a} {b} + 2 * 5 -",
        ]
        cases = list(zip(ids, expressions))
        secrets.SystemRandom().shuffle(cases)
        expected = {test_id: eval_rpn(expr) for test_id, expr in cases}

        wrapper = f'''#!/bin/bash
if [ "$#" -ne 1 ]; then
    printf 'BADARGS\\t%s\\n' "$#" >> {event_log!r}
    exit 91
fi
printf 'START\\t%s\\n' "$1" >> {event_log!r}
sleep 1
result=$("{real_interpreter}" "$1")
status=$?
printf 'END\\t%s\\n' "$1" >> {event_log!r}
[ "$status" -eq 0 ] || exit "$status"
printf '%s\\n' "$result"
'''

        try:
            with open(fixtures_path, "w") as f:
                for test_id, expression in cases:
                    f.write(f"{test_id},{expression}\n")

            with open(interpreter_path, "w") as f:
                f.write(wrapper)
            os.chmod(interpreter_path, 0o755)

            if os.path.isdir(data_path):
                shutil.rmtree(data_path)
            if os.path.exists(report_path):
                os.remove(report_path)

            with open(bash_env, "w") as f:
                f.write('wait() { printf "WAIT\\n" >> "$WAIT_LOG"; builtin wait "$@"; }\n')

            env = os.environ.copy()
            env["BASH_ENV"] = bash_env
            env["WAIT_LOG"] = wait_log
            run = subprocess.run(
                [runner],
                cwd="/home/user",
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
            )
            assert run.returncode == 0, f"Dynamic execution of test_runner.sh failed:\nstdout={run.stdout}\nstderr={run.stderr}"

            assert os.path.isfile(wait_log), "test_runner.sh never invoked Bash 'wait'"
            with open(wait_log) as f:
                assert any(line.strip() == "WAIT" for line in f), "test_runner.sh never invoked Bash 'wait'"

            assert os.path.isdir(data_path), "test_runner.sh did not create test_data"
            expected_names = {f"test_{test_id}.txt" for test_id, _ in cases}
            assert set(os.listdir(data_path)) == expected_names, "Migrated files do not match the dynamic CSV fixtures"
            for test_id, expression in cases:
                with open(os.path.join(data_path, f"test_{test_id}.txt")) as f:
                    content = f.read()
                assert content in (expression, expression + "\n"), f"Incorrect migrated expression for test {test_id}: {content!r}"

            assert os.path.isfile(event_log), "The runner never executed /home/user/interpreter.sh"
            with open(event_log) as f:
                events = [line.rstrip("\n") for line in f if line.strip()]
            assert not any(line.startswith("BADARGS") for line in events), "Expressions were not passed as one string argument"
            starts = [line.split("\t", 1)[1] for line in events if line.startswith("START\t")]
            ends = [line.split("\t", 1)[1] for line in events if line.startswith("END\t")]
            assert collections.Counter(starts) == collections.Counter(expressions), "Runner did not execute every dynamic fixture exactly once"
            assert collections.Counter(ends) == collections.Counter(expressions), "Runner did not wait for every interpreter execution to finish"
            first_end = next((i for i, line in enumerate(events) if line.startswith("END\t")), len(events))
            starts_before_first_end = [line for line in events[:first_end] if line.startswith("START\t")]
            assert len(starts_before_first_end) == len(expressions), "Interpreter executions were not all spawned concurrently as background jobs"

            with open(report_path) as f:
                report_lines = [line.strip() for line in f if line.strip()]
            expected_lines = [f"Test {test_id}: {expected[test_id]}" for test_id in sorted(expected)]
            assert report_lines == expected_lines, f"Dynamic report was incorrect or not numerically sorted. Expected {expected_lines}, got {report_lines}"
        finally:
            with open(fixtures_path, "wb") as f:
                f.write(original_fixtures)
            os.chmod(fixtures_path, original_fixtures_mode)
            with open(interpreter_path, "wb") as f:
                f.write(original_interpreter)
            os.chmod(interpreter_path, original_interpreter_mode)
            if os.path.isdir(data_path):
                shutil.rmtree(data_path)
            if os.path.isdir(saved_data):
                shutil.copytree(saved_data, data_path)
            if original_report is None:
                if os.path.exists(report_path):
                    os.remove(report_path)
            else:
                with open(report_path, "wb") as f:
                    f.write(original_report)
                os.chmod(report_path, original_report_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
