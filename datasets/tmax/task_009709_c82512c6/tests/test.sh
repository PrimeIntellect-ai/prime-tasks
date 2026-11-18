#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import collections
import json
import os
import shutil
import stat
import subprocess
import tempfile
import textwrap
import uuid

import pytest

REPO = "/home/user/decoder_project"
RUNNER = "/home/user/secure_runner.py"
OUTPUT = "/home/user/output.json"
KEY = "N0vA_s3cR3t_99xY"


def run_runner(timeout=30):
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    return subprocess.run(
        ["python3", RUNNER],
        cwd=REPO,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def test_bad_commit():
    bad_commit_file = "/home/user/bad_commit.txt"
    assert os.path.exists(bad_commit_file), f"{bad_commit_file} does not exist."

    with open(bad_commit_file, "r") as f:
        actual_commit = f.read().strip()

    res = subprocess.run(
        ["git", "log", "--grep=Optimize by adding multithreading", "--format=%H"],
        cwd=REPO, capture_output=True, text=True, check=True
    )
    expected_commit = res.stdout.strip()

    assert expected_commit, "Could not find the target commit in the repository."
    assert actual_commit == expected_commit, (
        f"Incorrect commit hash in {bad_commit_file}. Expected {expected_commit}, "
        f"got {actual_commit}"
    )


def test_secret_key():
    key_file = "/home/user/secret_key.txt"
    assert os.path.exists(key_file), f"{key_file} does not exist."

    with open(key_file, "r") as f:
        actual_key = f.read().strip()

    assert actual_key == KEY, f"Secret key in {key_file} is incorrect."


def test_secure_runner_script():
    assert os.path.exists(RUNNER), f"{RUNNER} does not exist."

    with open(RUNNER, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "ThreadPoolExecutor" in content, "secure_runner.py must use ThreadPoolExecutor."
    assert "Lock" in content or "lock" in content.lower(), "secure_runner.py must use a locking mechanism."

    try:
        tree = ast.parse(content, filename=RUNNER)
    except SyntaxError as exc:
        pytest.fail(f"secure_runner.py is not valid Python: {exc}")

    list_vars = set()
    lock_vars = set()
    executor_calls = []

    for node in tree.body:
        target = None
        value = None
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name):
            target, value = node.targets[0].id, node.value
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            target, value = node.target.id, node.value

        if target and isinstance(value, (ast.List, ast.ListComp)):
            list_vars.add(target)
        if target and isinstance(value, ast.Call):
            func_name = ast.unparse(value.func)
            if func_name.endswith("Lock") or func_name.endswith("RLock"):
                lock_vars.add(target)

    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and ast.unparse(node.func).endswith("ThreadPoolExecutor"):
            executor_calls.append(node)

    assert executor_calls, "secure_runner.py must instantiate ThreadPoolExecutor."

    def has_four_workers(call):
        for kw in call.keywords:
            if kw.arg == "max_workers" and isinstance(kw.value, ast.Constant) and kw.value.value == 4:
                return True
        return bool(call.args and isinstance(call.args[0], ast.Constant) and call.args[0].value == 4)

    assert any(has_four_workers(call) for call in executor_calls), (
        "ThreadPoolExecutor must be instantiated with exactly 4 workers."
    )
    assert list_vars, "secure_runner.py must define a global list for decoded results."
    assert lock_vars, "secure_runner.py must create a Lock for result collection."

    protected_append = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.With):
            continue
        context = " ".join(ast.unparse(item.context_expr) for item in node.items)
        if not any(name in context for name in lock_vars):
            continue
        for child in ast.walk(node):
            if (
                isinstance(child, ast.Call)
                and isinstance(child.func, ast.Attribute)
                and child.func.attr == "append"
                and isinstance(child.func.value, ast.Name)
                and child.func.value.id in list_vars
            ):
                protected_append = True

    # Also accept an explicit acquire/append/release sequence.
    if not protected_append:
        for node in ast.walk(tree):
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            calls = [n for n in ast.walk(node) if isinstance(n, ast.Call)]
            acquired = {
                n.func.value.id
                for n in calls
                if isinstance(n.func, ast.Attribute)
                and n.func.attr == "acquire"
                and isinstance(n.func.value, ast.Name)
                and n.func.value.id in lock_vars
            }
            released = {
                n.func.value.id
                for n in calls
                if isinstance(n.func, ast.Attribute)
                and n.func.attr == "release"
                and isinstance(n.func.value, ast.Name)
                and n.func.value.id in lock_vars
            }
            appended = any(
                isinstance(n.func, ast.Attribute)
                and n.func.attr == "append"
                and isinstance(n.func.value, ast.Name)
                and n.func.value.id in list_vars
                for n in calls
            )
            if acquired & released and appended:
                protected_append = True
                break

    assert protected_append, "Appending to the global result list must be protected by the Lock."


def test_runner_executes_on_original_inputs():
    result = run_runner()
    assert result.returncode == 0, (
        f"secure_runner.py failed with exit code {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )


def test_output_json():
    assert os.path.exists(OUTPUT), f"{OUTPUT} does not exist."

    with open(OUTPUT, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{OUTPUT} is not valid JSON.")

    assert isinstance(data, list), f"{OUTPUT} must contain a JSON array."
    assert len(data) == 98, f"Expected exactly 98 successful decodes, but found {len(data)}."

    expected = [f"Decoded: VALID_DATA_PAYLOAD_{i}" for i in range(1, 101) if i not in (42, 73)]
    assert sorted(data) == sorted(expected), (
        f"The contents of {OUTPUT} do not match the expected successfully decoded payloads."
    )


def test_runner_dynamic_execution_and_concurrency():
    audit_root = tempfile.mkdtemp(prefix="secure-runner-audit-")
    inputs = os.path.join(REPO, "inputs")
    decoder = os.path.join(REPO, "decoder.bin")
    saved_inputs = os.path.join(audit_root, "saved_inputs")
    real_decoder = os.path.join(audit_root, "real_decoder.bin")
    state_file = os.path.join(audit_root, "state.json")

    shutil.move(inputs, saved_inputs)
    shutil.copy2(decoder, real_decoder)
    os.mkdir(inputs)

    token = uuid.uuid4().hex
    valid_payloads = [f"AUDIT_{token}_{i}" for i in range(9)]
    corrupt_payloads = [f"AUDIT_{token}_CORRUPT_{i}" for i in range(3)]
    generated_paths = []

    for i, payload in enumerate(valid_payloads + corrupt_payloads):
        path = os.path.join(inputs, f"audit_{i}.txt")
        with open(path, "w") as f:
            f.write(payload + "\n")
        generated_paths.append(os.path.realpath(path))

    wrapper = textwrap.dedent(f'''\
        #!/usr/bin/env python3
        import fcntl
        import json
        import subprocess
        import sys
        import time

        STATE = {state_file!r}
        REAL = {real_decoder!r}

        def update(delta, record=False):
            with open(STATE, "a+") as f:
                fcntl.flock(f.fileno(), fcntl.LOCK_EX)
                f.seek(0)
                raw = f.read()
                state = json.loads(raw) if raw else {{"current": 0, "maximum": 0, "calls": []}}
                state["current"] += delta
                state["maximum"] = max(state["maximum"], state["current"])
                if record:
                    state["calls"].append(sys.argv[1:])
                f.seek(0)
                f.truncate()
                json.dump(state, f)
                f.flush()
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)

        update(1, True)
        try:
            time.sleep(0.20)
            result = subprocess.run([REAL] + sys.argv[1:], capture_output=True)
            sys.stdout.buffer.write(result.stdout)
            sys.stderr.buffer.write(result.stderr)
            code = result.returncode
        finally:
            update(-1)
        sys.exit(code)
    ''')

    try:
        with open(decoder, "w") as f:
            f.write(wrapper)
        os.chmod(decoder, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                          stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

        result = run_runner(timeout=30)
        assert result.returncode == 0, (
            f"secure_runner.py did not gracefully handle decoder failures.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert os.path.exists(OUTPUT), "secure_runner.py did not create output.json."

        with open(OUTPUT) as f:
            data = json.load(f)
        expected = sorted(f"Decoded: {payload}" for payload in valid_payloads)
        assert isinstance(data, list), "Dynamic output must be a JSON array."
        assert sorted(data) == expected, (
            "Dynamic output must contain only successful decoder stdout and ignore corrupt inputs."
        )

        with open(state_file) as f:
            state = json.load(f)

        assert state["maximum"] == 4, (
            f"Expected exactly 4 decoder jobs to run concurrently; observed {state['maximum']}."
        )
        assert len(state["calls"]) == len(generated_paths), (
            "The runner must invoke decoder.bin once for every .txt input."
        )

        actual_paths = []
        for call in state["calls"]:
            assert len(call) == 2, "decoder.bin must receive exactly the secret key and file path."
            assert call[0] == KEY, "decoder.bin was invoked with the wrong secret key."
            path_arg = call[1]
            if not os.path.isabs(path_arg):
                path_arg = os.path.join(REPO, path_arg)
            actual_paths.append(os.path.realpath(path_arg))

        assert collections.Counter(actual_paths) == collections.Counter(generated_paths), (
            "decoder.bin was not invoked exactly once for every generated input file."
        )
    finally:
        if os.path.exists(inputs):
            shutil.rmtree(inputs)
        shutil.move(saved_inputs, inputs)
        shutil.copy2(real_decoder, decoder)
        shutil.rmtree(audit_root, ignore_errors=True)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
