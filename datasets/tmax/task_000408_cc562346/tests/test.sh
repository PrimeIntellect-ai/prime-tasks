#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import stat
import subprocess
import tempfile
import time
import uuid

REPO = "/home/user/edge-firmware.git"
HOOK = REPO + "/hooks/post-receive"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kwargs)


def test_bare_git_repo():
    repo_path = "/home/user/edge-firmware.git"
    assert os.path.isdir(repo_path), f"Git repository directory not found at {repo_path}"

    config_path = os.path.join(repo_path, "config")
    assert os.path.isfile(config_path), f"Git config not found at {config_path}"

    with open(config_path, "r") as f:
        config_content = f.read()

    assert "bare = true" in config_content.lower(), f"Repository at {repo_path} is not configured as a bare repository."
    result = run(["git", "--git-dir", repo_path, "rev-parse", "--is-bare-repository"])
    assert result.stdout.strip() == "true"
    run(["git", "--git-dir", repo_path, "rev-parse", "--verify", "refs/heads/main"])


def test_staging_permissions():
    staged_file = "/home/user/deploy_staging/firmware.json"
    assert os.path.isfile(staged_file), f"Staged file not found at {staged_file}"

    st = os.stat(staged_file)
    permissions = stat.S_IMODE(st.st_mode)

    assert permissions == 0o600, f"Permissions on {staged_file} are {oct(permissions)}, expected 0o600"


def test_device_update_log():
    log_file = "/home/user/device_update.log"
    assert os.path.isfile(log_file), f"Device update log not found at {log_file}. pexpect interaction may have failed."

    source_file = "/home/user/source_code/firmware.json"
    assert os.path.isfile(source_file), f"Source file missing at {source_file}"

    with open(source_file, "r") as f:
        source_content = f.read().strip()

    with open(log_file, "r") as f:
        log_content = f.read().strip()

    assert log_content == source_content, f"Payload in {log_file} does not match the source firmware.json"


def test_email_outbox():
    outbox_file = "/home/user/email_outbox.log"
    assert os.path.isfile(outbox_file), f"Email outbox log not found at {outbox_file}. Email was not sent."

    with open(outbox_file, "r") as f:
        outbox_content = f.read()

    assert "deploybot@edge.local" in outbox_content, "Sender 'deploybot@edge.local' not found in email outbox log."
    assert "alerts@edge.local" in outbox_content, "Recipient 'alerts@edge.local' not found in email outbox log."
    assert "The firmware was successfully updated" in outbox_content, "Expected success message not found in email body."


def test_hook_is_executable_python_using_pexpect():
    assert os.path.isfile(HOOK), f"post-receive hook not found at {HOOK}"
    assert os.access(HOOK, os.X_OK), "post-receive hook is not executable"

    with open(HOOK, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=HOOK)
    except SyntaxError as exc:
        raise AssertionError(f"post-receive hook is not valid Python: {exc}")

    module_aliases = set()
    spawn_aliases = set()
    imported_pexpect = False
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == "pexpect":
                    imported_pexpect = True
                    module_aliases.add(alias.asname or "pexpect")
        elif isinstance(node, ast.ImportFrom) and node.module == "pexpect":
            imported_pexpect = True
            for alias in node.names:
                if alias.name == "spawn":
                    spawn_aliases.add(alias.asname or alias.name)

    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
    has_spawn = any(
        (isinstance(c.func, ast.Attribute) and c.func.attr == "spawn" and
         isinstance(c.func.value, ast.Name) and c.func.value.id in module_aliases)
        or (isinstance(c.func, ast.Name) and c.func.id in spawn_aliases)
        for c in calls
    )
    called_methods = {
        c.func.attr for c in calls if isinstance(c.func, ast.Attribute)
    }
    assert imported_pexpect, "hook does not import pexpect"
    assert has_spawn, "hook does not call pexpect.spawn"
    assert "expect" in called_methods or "expect_exact" in called_methods, "hook does not use pexpect expect operations"
    assert "sendline" in called_methods or "send" in called_methods, "hook does not send device input through pexpect"


def test_z_fresh_push_triggers_complete_pipeline():
    trace_dir = tempfile.mkdtemp(prefix="pexpect_site_")
    trace_file = os.path.join(trace_dir, "trace.jsonl")
    sitecustomize = r'''
import json
import os
try:
    import pexpect
    _real_spawn = pexpect.spawn
    _trace_path = os.environ.get("PEXPECT_TRACE_FILE")

    def _record(kind, **fields):
        if not _trace_path:
            return
        rec = {"kind": kind}
        rec.update(fields)
        with open(_trace_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(rec) + "\\n")

    class _TracedChild:
        def __init__(self, child):
            object.__setattr__(self, "_child", child)
        def __getattr__(self, name):
            return getattr(self._child, name)
        def __setattr__(self, name, value):
            if name == "_child":
                object.__setattr__(self, name, value)
            else:
                setattr(self._child, name, value)
        def expect(self, pattern, *args, **kwargs):
            result = self._child.expect(pattern, *args, **kwargs)
            _record("expect", pattern=repr(pattern))
            return result
        def expect_exact(self, pattern, *args, **kwargs):
            result = self._child.expect_exact(pattern, *args, **kwargs)
            _record("expect", pattern=repr(pattern))
            return result
        def sendline(self, data=b""):
            result = self._child.sendline(data)
            _record("sendline", data=data.decode("utf-8") if isinstance(data, bytes) else str(data))
            return result
        def send(self, data):
            result = self._child.send(data)
            _record("send", data=data.decode("utf-8") if isinstance(data, bytes) else str(data))
            return result

    def _spawn(*args, **kwargs):
        child = _real_spawn(*args, **kwargs)
        _record("spawn", command=repr(args), kwargs=repr(kwargs))
        return _TracedChild(child)

    pexpect.spawn = _spawn
except Exception:
    pass
'''
    with open(os.path.join(trace_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
        f.write(sitecustomize)

    nonce = uuid.uuid4().hex
    expected = json.dumps(
        {"version": "verify-" + nonce, "build": "stable", "features": ["wifi", "ble"]},
        separators=(",", ":"),
    )

    for path in [
        "/home/user/device_update.log",
        "/home/user/email_outbox.log",
        "/home/user/deploy_staging/firmware.json",
    ]:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["PYTHONPATH"] = trace_dir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["PEXPECT_TRACE_FILE"] = trace_file
    env["GIT_CONFIG_COUNT"] = "1"
    env["GIT_CONFIG_KEY_0"] = "safe.directory"
    env["GIT_CONFIG_VALUE_0"] = "*"

    with tempfile.TemporaryDirectory(prefix="firmware_push_") as work:
        run(["git", "clone", REPO, work], env=env, timeout=30)
        run(["git", "-C", work, "checkout", "main"], env=env, timeout=30)
        run(["git", "-C", work, "config", "user.email", "verifier@edge.local"], env=env)
        run(["git", "-C", work, "config", "user.name", "Pipeline Verifier"], env=env)
        with open(os.path.join(work, "firmware.json"), "w", encoding="utf-8") as f:
            f.write(expected + "\n")
        run(["git", "-C", work, "add", "firmware.json"], env=env)
        run(["git", "-C", work, "commit", "-m", "Verifier firmware " + nonce], env=env)
        pushed_commit = run(["git", "-C", work, "rev-parse", "HEAD"], env=env).stdout.strip()
        run(["git", "-C", work, "push", "origin", "HEAD:main"], env=env, timeout=30)

    remote_commit = run(["git", "--git-dir", REPO, "rev-parse", "refs/heads/main"], env=env).stdout.strip()
    assert remote_commit == pushed_commit, "fresh main commit was not accepted by the bare repository"

    staged = "/home/user/deploy_staging/firmware.json"
    assert os.path.isfile(staged), "hook did not check out firmware.json into deploy_staging"
    with open(staged, "r", encoding="utf-8") as f:
        assert f.read().strip() == expected, "staging contains something other than the freshly pushed payload"
    assert stat.S_IMODE(os.stat(staged).st_mode) == 0o600, "freshly staged firmware.json is not mode 0600"

    with open("/home/user/device_update.log", "r", encoding="utf-8") as f:
        assert f.read().strip() == expected, "device did not receive the freshly generated payload"

    deadline = time.time() + 3
    outbox = ""
    while time.time() < deadline:
        if os.path.isfile("/home/user/email_outbox.log"):
            with open("/home/user/email_outbox.log", "r", encoding="utf-8") as f:
                outbox = f.read()
            if "The firmware was successfully updated." in outbox:
                break
        time.sleep(0.1)
    assert "deploybot@edge.local" in outbox
    assert "alerts@edge.local" in outbox
    assert "Subject: Deploy Success" in outbox
    assert "The firmware was successfully updated." in outbox

    assert os.path.isfile(trace_file), "the hook did not execute pexpect during the fresh push"
    with open(trace_file, "r", encoding="utf-8") as f:
        events = [json.loads(line) for line in f if line.strip()]

    spawn_events = [e for e in events if e.get("kind") == "spawn"]
    assert any("/usr/bin/python3" in e.get("command", "") and "/home/user/edge_vm.py" in e.get("command", "") for e in spawn_events), \
        "hook did not spawn /usr/bin/python3 /home/user/edge_vm.py with pexpect"

    position = 0
    sequence = [
        ("expect", "login: "),
        ("send", "admin"),
        ("expect", "password: "),
        ("send", "edge_secure_99"),
        ("expect", "Device> "),
        ("send", "update"),
        ("expect", "Ready for payload: "),
        ("send", expected),
        ("expect", "Update SUCCESS"),
    ]
    for wanted_kind, wanted_value in sequence:
        found = False
        while position < len(events):
            event = events[position]
            position += 1
            kind = event.get("kind", "")
            if wanted_kind == "send":
                if kind in ("send", "sendline") and event.get("data", "").rstrip("\r\n") == wanted_value:
                    found = True
                    break
            elif kind == "expect" and wanted_value in event.get("pattern", ""):
                found = True
                break
        assert found, f"missing or out-of-order pexpect operation: {wanted_kind} {wanted_value!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
