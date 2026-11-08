#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import subprocess
import textwrap

HOME = "/home/user"
VENV_PYTHON = f"{HOME}/venv/bin/python"
VENV_PYTEST = f"{HOME}/venv/bin/pytest"


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 180)
    return subprocess.run(cmd, **kwargs)


def test_venv_and_packages():
    assert os.path.isfile(VENV_PYTHON), f"Virtual environment python not found at {VENV_PYTHON}"
    result = run([VENV_PYTHON, "-c", "import pytest, hypothesis, responses, requests"])
    assert result.returncode == 0, f"Failed to import required packages in venv. Error: {result.stderr}"


def test_sync_source_uses_required_lock_context():
    path = f"{HOME}/sync_manager.py"
    assert os.path.isfile(path), f"{path} does not exist"
    with open(path, encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=path)

    classes = [n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == "SyncManager"]
    assert classes, "SyncManager class is missing"
    methods = [n for n in classes[0].body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == "sync"]
    assert methods, "SyncManager.sync is missing"
    method = methods[0]

    body = list(method.body)
    if body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant) and isinstance(body[0].value.value, str):
        body = body[1:]
    assert len(body) == 1 and isinstance(body[0], ast.With), \
        "The entire sync operation must be enclosed by one 'with self.lock:' statement"
    lock_with = body[0]
    assert len(lock_with.items) == 1
    context = lock_with.items[0].context_expr
    assert (isinstance(context, ast.Attribute) and context.attr == "lock" and
            isinstance(context.value, ast.Name) and context.value.id == "self"), \
        "SyncManager.sync must use exactly 'with self.lock:'"

    nested = list(ast.walk(lock_with))
    post_calls = [n for n in nested if isinstance(n, ast.Call) and
                  isinstance(n.func, ast.Attribute) and n.func.attr == "post" and
                  isinstance(n.func.value, ast.Name) and n.func.value.id == "requests"]
    raise_calls = [n for n in nested if isinstance(n, ast.Call) and
                   isinstance(n.func, ast.Attribute) and n.func.attr == "raise_for_status"]
    assert post_calls, "requests.post must be executed inside with self.lock"
    assert raise_calls, "response.raise_for_status must be executed inside with self.lock"

    def is_self_cache(node):
        return (isinstance(node, ast.Attribute) and node.attr == "cache" and
                isinstance(node.value, ast.Name) and node.value.id == "self")

    mutations = []
    for node in nested:
        if isinstance(node, (ast.Assign, ast.AnnAssign, ast.AugAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            for target in targets:
                if is_self_cache(target) or (isinstance(target, ast.Subscript) and is_self_cache(target.value)):
                    mutations.append(node)
        elif (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and
              is_self_cache(node.func.value) and node.func.attr in
              {"update", "clear", "pop", "popitem", "setdefault", "__setitem__"}):
            mutations.append(node)
    assert mutations, "sync must commit successful data to self.cache"
    first_raise = min(n.lineno for n in raise_calls)
    assert all(n.lineno > first_raise for n in mutations), \
        "self.cache must not be modified before response.raise_for_status succeeds"


def test_submission_property_test_is_substantive_and_passes():
    path = f"{HOME}/test_sync.py"
    assert os.path.isfile(path), f"{path} does not exist"
    with open(path, encoding="utf-8") as f:
        source = f.read()
    tree = ast.parse(source, filename=path)
    funcs = [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == "test_sync_atomicity"]
    assert funcs, "test_sync_atomicity() is missing"
    func = funcs[0]

    decorators = list(func.decorator_list)
    assert any(isinstance(n, ast.Call) and
               ((isinstance(n.func, ast.Name) and n.func.id == "given") or
                (isinstance(n.func, ast.Attribute) and n.func.attr == "given"))
               for n in decorators), "test_sync_atomicity must use Hypothesis @given"
    calls = [n for n in ast.walk(func) if isinstance(n, ast.Call)]
    attrs = {n.func.attr for n in calls if isinstance(n.func, ast.Attribute)}
    assert "dictionaries" in attrs and "text" in attrs, \
        "test_sync_atomicity must generate dictionaries with text strategies"
    assert "responses" in source and ("activate" in source or "RequestsMock" in source), \
        "test_sync_atomicity must use responses to mock the API"
    constants = {n.value for n in ast.walk(func) if isinstance(n, ast.Constant)}
    assert 200 in constants and 500 in constants, "The property test must exercise both HTTP 200 and HTTP 500"
    assert any(isinstance(n, ast.Assert) for n in ast.walk(func)), \
        "test_sync_atomicity must contain assertions"

    assert os.path.isfile(VENV_PYTEST), f"pytest not found in venv at {VENV_PYTEST}"
    result = run([VENV_PYTEST, path], cwd=HOME)
    assert result.returncode == 0, f"test_sync.py failed to pass. Output:\n{result.stdout}\n{result.stderr}"


def test_sync_manager_logic_varied_and_concurrent():
    helper = "/tmp/verify_sync_behavior.py"
    with open(helper, "w", encoding="utf-8") as f:
        f.write(textwrap.dedent(r'''
            import secrets
            import threading
            import time
            import requests
            from sync_manager import SyncManager

            class FakeResponse:
                def __init__(self, fail=False):
                    self.fail = fail
                def raise_for_status(self):
                    if self.fail:
                        raise requests.HTTPError("generated failure")

            original_post = requests.post
            try:
                # Derive many non-fixed cases and require exact merge/rollback behavior.
                for i in range(24):
                    manager = SyncManager()
                    prior = {"prior_" + secrets.token_hex(4): secrets.token_hex(6),
                             "shared": secrets.token_hex(5)}
                    new_data = {"new_" + secrets.token_hex(4): secrets.token_hex(6),
                                "shared": secrets.token_hex(5)}
                    manager.cache = prior.copy()
                    expected = prior.copy()
                    expected.update(new_data)
                    should_fail = (i % 2 == 1)
                    seen = []

                    def fake_post(url, json=None, **kwargs):
                        assert url == "http://api.example.com/sync"
                        seen.append(dict(json))
                        return FakeResponse(should_fail)

                    requests.post = fake_post
                    try:
                        manager.sync(new_data)
                        assert not should_fail, "A failing HTTP response did not propagate"
                    except requests.HTTPError:
                        assert should_fail
                    assert seen == [expected], "POST payload was not the proposed complete cache"
                    assert manager.cache == (prior if should_fail else expected), \
                        "Cache did not commit exactly on success or roll back exactly on failure"

                # A slow mocked API exposes implementations that do not hold the lock
                # across the whole operation. Proper locking permits only one active POST.
                manager = SyncManager()
                active = 0
                maximum_active = 0
                guard = threading.Lock()
                start = threading.Barrier(6)

                def slow_post(url, json=None, **kwargs):
                    global active, maximum_active
                    assert url == "http://api.example.com/sync"
                    with guard:
                        active += 1
                        maximum_active = max(maximum_active, active)
                    time.sleep(0.04)
                    with guard:
                        active -= 1
                    return FakeResponse(False)

                requests.post = slow_post
                errors = []
                def worker(index):
                    try:
                        start.wait()
                        manager.sync({"thread_" + str(index): secrets.token_hex(4)})
                    except BaseException as exc:
                        errors.append(exc)

                threads = [threading.Thread(target=worker, args=(i,)) for i in range(6)]
                for thread in threads:
                    thread.start()
                for thread in threads:
                    thread.join(10)
                assert all(not thread.is_alive() for thread in threads), "Concurrent sync calls deadlocked"
                assert not errors, repr(errors)
                assert maximum_active == 1, "Concurrent sync calls entered the API operation simultaneously"
                assert set(manager.cache) == {"thread_" + str(i) for i in range(6)}, \
                    "Concurrent successful updates were lost"
            finally:
                requests.post = original_post
        '''))
    result = run([VENV_PYTHON, helper], cwd=HOME, timeout=60)
    assert result.returncode == 0, f"SyncManager behavioral verification failed:\n{result.stdout}\n{result.stderr}"


def test_original_fixed_logic_case():
    helper = "/tmp/verify_original_case.py"
    with open(helper, "w", encoding="utf-8") as f:
        f.write(textwrap.dedent('''
            from sync_manager import SyncManager
            import responses

            @responses.activate
            def check():
                manager = SyncManager()
                manager.cache = {"a": 1}
                responses.add(responses.POST, "http://api.example.com/sync", status=500)
                try:
                    manager.sync({"b": 2})
                except Exception:
                    pass
                assert manager.cache == {"a": 1}
                responses.add(responses.POST, "http://api.example.com/sync", status=200)
                manager.sync({"b": 2})
                assert manager.cache == {"a": 1, "b": 2} or manager.cache == {"b": 2}
            check()
        '''))
    result = run([VENV_PYTHON, helper], cwd=HOME)
    assert result.returncode == 0, f"Original logic verification failed:\n{result.stdout}\n{result.stderr}"


def test_analyze_script_executes_and_bytecode_is_genuine():
    analyze_path = f"{HOME}/analyze.py"
    bytecode_path = f"{HOME}/bytecode.txt"
    assert os.path.isfile(analyze_path), f"{analyze_path} does not exist"
    if os.path.exists(bytecode_path):
        os.remove(bytecode_path)

    result = run([VENV_PYTHON, analyze_path], cwd=HOME)
    assert result.returncode == 0, f"analyze.py failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(bytecode_path), f"{bytecode_path} was not created by analyze.py"
    with open(bytecode_path, encoding="utf-8") as f:
        content = f.read()
    assert "self" in content, "bytecode.txt does not contain 'self'"
    assert "lock" in content, "bytecode.txt does not contain 'lock'"

    expected_path = "/tmp/expected_bytecode.txt"
    code = textwrap.dedent(f'''
        import contextlib, dis
        from sync_manager import SyncManager
        with open({expected_path!r}, "w", encoding="utf-8") as out:
            with contextlib.redirect_stdout(out):
                dis.dis(SyncManager.sync)
    ''')
    expected_result = run([VENV_PYTHON, "-c", code], cwd=HOME)
    assert expected_result.returncode == 0, expected_result.stderr
    with open(expected_path, encoding="utf-8") as f:
        expected = f.read()
    assert content == expected, "bytecode.txt is not the actual human-readable disassembly of SyncManager.sync"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
