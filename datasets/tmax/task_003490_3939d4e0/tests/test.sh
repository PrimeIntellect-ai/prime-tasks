#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import stat
import subprocess
import tempfile
import textwrap
import py_compile


def test_00_execute_fix_and_run_with_pexpect_audit():
    # Restore the relevant files to their initial state so the submitted Python
    # script, rather than pre-fabricated final artifacts, must perform the work.
    worker_path = "/home/user/app/worker.py"
    with open(worker_path, "w") as f:
        f.write(textwrap.dedent('''\
            import sys

            def main():
                sys.stderr.write("Passkey: ")
                sys.stderr.flush()
                key = sys.stdin.readline().strip()
                if key == "DEPLOY_V2_READY":
                    print("Worker updated successfully.")
                else:
                    print("Invalid passkey.")
                    sys.exit(1)

            if __name__ == "__main__":
                main()
        '''))

    deploy_path = "/home/user/app/deploy.sh"
    with open(deploy_path, "w") as f:
        f.write("#!/bin/bash\npython3 worker.py > deploy.log\n")
    os.chmod(deploy_path, 0o644)

    log_path = "/home/user/app/deploy.log"
    if os.path.lexists(log_path):
        os.unlink(log_path)

    script_path = "/home/user/fix_and_run.py"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."

    audit_dir = tempfile.mkdtemp(prefix="pexpect_audit_")
    trace_path = os.path.join(audit_dir, "trace.jsonl")
    sitecustomize = r'''
import json
import os

_trace = os.environ.get("PEXPECT_AUDIT_TRACE")

def _record(event):
    if _trace:
        with open(_trace, "a") as _f:
            _f.write(json.dumps(event) + "\\n")

try:
    import pexpect
except ImportError:
    pexpect = None

if pexpect is not None:
    _real_spawn = pexpect.spawn

    def _has_prompt(pattern):
        if isinstance(pattern, (list, tuple)):
            return any(_has_prompt(item) for item in pattern)
        return pattern == "Passkey:" or pattern == b"Passkey:"

    def _has_eof(pattern):
        if isinstance(pattern, (list, tuple)):
            return any(_has_eof(item) for item in pattern)
        return pattern is pexpect.EOF

    def _audited_spawn(*args, **kwargs):
        child = _real_spawn(*args, **kwargs)
        command = args[0] if args else kwargs.get("command")
        _record({"event": "spawn", "command": str(command)})

        for method_name in ("expect", "expect_exact"):
            real_method = getattr(child, method_name)
            def audited_expect(pattern, *a, _real=real_method, _name=method_name, **kw):
                result = _real(pattern, *a, **kw)
                _record({
                    "event": _name,
                    "prompt": _has_prompt(pattern),
                    "eof": _has_eof(pattern),
                })
                return result
            setattr(child, method_name, audited_expect)

        for method_name in ("send", "sendline"):
            real_method = getattr(child, method_name)
            def audited_send(data, *a, _real=real_method, _name=method_name, **kw):
                result = _real(data, *a, **kw)
                if isinstance(data, bytes):
                    rendered = data.decode("utf-8", "replace")
                else:
                    rendered = str(data)
                _record({"event": _name, "data": rendered})
                return result
            setattr(child, method_name, audited_send)

        return child

    pexpect.spawn = _audited_spawn
'''
    with open(os.path.join(audit_dir, "sitecustomize.py"), "w") as f:
        f.write(sitecustomize)

    env = os.environ.copy()
    env["PEXPECT_AUDIT_TRACE"] = trace_path
    env["PYTHONPATH"] = audit_dir + os.pathsep + env.get("PYTHONPATH", "")

    try:
        proc = subprocess.run(
            ["python3", script_path],
            cwd="/",
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
    except subprocess.TimeoutExpired:
        assert False, "fix_and_run.py did not finish within 20 seconds."

    assert proc.returncode == 0, (
        f"fix_and_run.py exited with status {proc.returncode}.\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}"
    )
    assert os.path.isfile(trace_path), "fix_and_run.py did not use the instrumented pexpect library."

    with open(trace_path) as f:
        events = [json.loads(line) for line in f if line.strip()]

    assert any(
        event.get("event") == "spawn"
        and event.get("command") == "/home/user/app/deploy.sh"
        for event in events
    ), "fix_and_run.py did not use pexpect.spawn on /home/user/app/deploy.sh."
    assert any(
        event.get("event") in ("expect", "expect_exact") and event.get("prompt")
        for event in events
    ), "fix_and_run.py did not successfully expect the exact Passkey: prompt."
    assert any(
        event.get("event") in ("send", "sendline")
        and event.get("data", "").rstrip("\r\n") == "DEPLOY_V2_READY"
        for event in events
    ), "fix_and_run.py did not send the required passkey through pexpect."
    assert any(
        event.get("event") in ("expect", "expect_exact") and event.get("eof")
        for event in events
    ), "fix_and_run.py did not wait for pexpect.EOF."


def test_fix_and_run_script_exists_and_valid():
    script_path = "/home/user/fix_and_run.py"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."

    try:
        py_compile.compile(script_path, doraise=True)
    except Exception as e:
        assert False, f"The script {script_path} contains invalid Python syntax: {e}"


def test_deploy_sh_content():
    deploy_path = "/home/user/app/deploy.sh"
    assert os.path.isfile(deploy_path), f"The script {deploy_path} does not exist."

    with open(deploy_path, "r") as f:
        content = f.read().strip()

    expected_content = "#!/bin/bash\n/usr/bin/python3 /home/user/app/worker.py > /home/user/app/deploy.log"
    assert content == expected_content, f"The content of {deploy_path} is incorrect. Expected:\n{expected_content}\nGot:\n{content}"


def test_deploy_sh_permissions():
    deploy_path = "/home/user/app/deploy.sh"
    assert os.path.isfile(deploy_path), f"The script {deploy_path} does not exist."

    st = os.stat(deploy_path)
    perms = oct(st.st_mode)[-3:]
    assert perms == "755", f"Permissions for {deploy_path} are {perms}, but should be 755."


def test_deploy_log_content():
    log_path = "/home/user/app/deploy.log"
    assert os.path.isfile(log_path), f"The log file {log_path} does not exist. Did the script run successfully?"

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_content = "Worker updated successfully."
    assert content == expected_content, f"The content of {log_path} is incorrect. Expected '{expected_content}', got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
