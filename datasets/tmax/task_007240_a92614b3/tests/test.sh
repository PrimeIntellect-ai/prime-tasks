#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import runpy
import stat
import subprocess
import tempfile
import time
import urllib.request
import uuid

LOCAL = "/home/user/local_clone"
BARE = "/home/user/api.git"
DEPLOYED = "/home/user/api_app"
CONF = "/home/user/supervisord.conf"


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 30)
    result = subprocess.run(cmd, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {cmd}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def local_git(*args):
    return run(["git", "-c", f"safe.directory={LOCAL}", "-C", LOCAL, *args])


def bare_git(*args):
    return run(["git", "-c", f"safe.directory={BARE}", f"--git-dir={BARE}", *args])


def assert_services_running():
    result = run(["supervisorctl", "-c", CONF, "status"])
    stdout = result.stdout
    assert "webapp" in stdout, "webapp service not found in supervisorctl status."
    assert "metrics" in stdout, "metrics service not found in supervisorctl status."
    lines = stdout.strip().splitlines()
    for name in ("webapp", "metrics"):
        matching = [line for line in lines if line.split() and line.split()[0] == name]
        assert matching, f"{name} service not found in supervisorctl status."
        assert "RUNNING" in matching[0], f"Service not running. Status line: {matching[0]}"


def test_final_state():
    # Preserve the push-log assertion, while requiring output shaped like a real push.
    log_path = "/home/user/push_output.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."
    with open(log_path, "r", errors="replace") as f:
        push_output = f.read()
    assert push_output.strip(), f"{log_path} is empty."
    assert re.search(r"(?m)^To .*(?:/|:)api\.git\s*$", push_output), \
        "push_output.log does not contain the destination line from git push."
    assert "main" in push_output or "up-to-date" in push_output.lower(), \
        "push_output.log does not show the main-branch push result."

    # Preserve the hook's file, executable, and command-content assertions.
    hook_path = f"{BARE}/hooks/post-receive"
    assert os.path.isfile(hook_path), f"Git hook {hook_path} does not exist."
    assert os.access(hook_path, os.X_OK), f"Git hook {hook_path} is not executable."
    with open(hook_path, "r", errors="replace") as f:
        hook_content = f.read()
    assert (
        "GIT_WORK_TREE=/home/user/api_app git checkout -f" in hook_content
        or "git --work-tree=/home/user/api_app checkout -f" in hook_content
        or "git checkout" in hook_content
    ), "Git hook missing checkout command."
    assert "supervisorctl" in hook_content and "restart all" in hook_content, \
        "Git hook missing supervisorctl restart all command."

    metrics_path = f"{LOCAL}/metrics.py"
    deployed_metrics = f"{DEPLOYED}/metrics.py"
    assert os.path.isfile(metrics_path), f"{metrics_path} does not exist."
    assert os.path.isfile(deployed_metrics), f"{deployed_metrics} does not exist."

    # The modified metrics.py must be committed, pushed to origin/main, and deployed
    # from that exact bare-repository commit rather than copied between mutable files.
    local_head = local_git("rev-parse", "HEAD").stdout.strip()
    bare_head = bare_git("rev-parse", "refs/heads/main").stdout.strip()
    assert local_head == bare_head, "The local HEAD was not pushed to origin/main."
    local_git("diff", "--quiet", "HEAD", "--", "metrics.py")
    local_git("diff", "--cached", "--quiet", "HEAD", "--", "metrics.py")

    root_commit = local_git("rev-list", "--max-parents=0", "HEAD").stdout.splitlines()[0]
    original_metrics = local_git("show", f"{root_commit}:metrics.py").stdout
    committed_metrics = local_git("show", "HEAD:metrics.py").stdout
    assert committed_metrics != original_metrics, "metrics.py was not modified from the initial commit."
    changed_commits = local_git("log", "--format=%H", f"{root_commit}..HEAD", "--", "metrics.py").stdout.strip()
    assert changed_commits, "No commit after the initial commit records the metrics.py modification."

    with open(metrics_path, "r") as f:
        local_content = f.read()
    with open(deployed_metrics, "r") as f:
        deployed_content = f.read()
    bare_content = bare_git("show", "refs/heads/main:metrics.py").stdout
    assert local_content == deployed_content, \
        "Deployed metrics.py does not match the local clone. Did the git push and post-receive hook work?"
    assert local_content == committed_metrics == bare_content, \
        "metrics.py is not the committed origin/main version."

    # Execute metrics.py with deterministic connection failures. It must make exactly
    # five attempts, sleep one second only between attempts, and then terminate.
    attempts = []
    sleeps = []
    original_urlopen = urllib.request.urlopen
    original_sleep = time.sleep

    def failing_urlopen(url, *args, **kwargs):
        attempts.append(str(url))
        raise ConnectionRefusedError("verifier-induced connection failure")

    def recorded_sleep(seconds):
        sleeps.append(seconds)
        if len(sleeps) > 10:
            raise RuntimeError("metrics.py entered an uncontrolled sleep loop")

    urllib.request.urlopen = failing_urlopen
    time.sleep = recorded_sleep
    outcome = None
    try:
        runpy.run_path(metrics_path, run_name="__main__")
    except BaseException as exc:
        outcome = exc
    finally:
        urllib.request.urlopen = original_urlopen
        time.sleep = original_sleep

    assert outcome is not None, "metrics.py returned normally after all connection attempts failed."
    assert len(attempts) == 5, f"Expected 5 connection attempts, observed {len(attempts)}."
    assert all(url == "http://localhost:8080" for url in attempts), \
        f"metrics.py attempted unexpected URLs: {attempts}"
    assert len(sleeps) == 4 and all(float(value) == 1.0 for value in sleeps), \
        f"Expected four 1-second sleeps between five attempts, observed {sleeps}."

    # Preserve and perform the supervisor status check after allowing stabilization.
    time.sleep(3)
    assert_services_running()

    # Exercise the real receive hook through a new push. A PATH-injected supervisorctl
    # records the requested command without disrupting the already-running services.
    with tempfile.TemporaryDirectory(prefix="verify_hook_") as td:
        clone = os.path.join(td, "clone")
        fake_bin = os.path.join(td, "bin")
        supervisor_log = os.path.join(td, "supervisorctl.log")
        os.mkdir(fake_bin)
        fake_ctl = os.path.join(fake_bin, "supervisorctl")
        with open(fake_ctl, "w") as f:
            f.write('#!/bin/sh\nprintf "%s\\n" "$*" >> "$VERIFY_SUPERVISOR_LOG"\n')
        os.chmod(fake_ctl, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR)

        run(["git", "-c", f"safe.directory={BARE}", "clone", BARE, clone])
        marker_name = f".verifier_hook_{uuid.uuid4().hex}"
        marker_value = uuid.uuid4().hex
        with open(os.path.join(clone, marker_name), "w") as f:
            f.write(marker_value + "\n")
        run(["git", "-C", clone, "config", "user.email", "verifier@example.invalid"])
        run(["git", "-C", clone, "config", "user.name", "Verifier"])
        run(["git", "-C", clone, "add", marker_name])
        run(["git", "-C", clone, "commit", "-m", "Verifier hook exercise"])

        env = os.environ.copy()
        env["PATH"] = fake_bin + os.pathsep + env.get("PATH", "")
        env["VERIFY_SUPERVISOR_LOG"] = supervisor_log
        run(["git", "-C", clone, "push", "origin", "main"], env=env)

        deployed_marker = os.path.join(DEPLOYED, marker_name)
        assert os.path.isfile(deployed_marker), \
            "A verifier push did not cause the post-receive hook to check out the new commit."
        with open(deployed_marker) as f:
            assert f.read().strip() == marker_value, \
                "The post-receive checkout did not deploy the pushed content."
        assert os.path.isfile(supervisor_log), \
            "The executed post-receive hook did not invoke supervisorctl."
        with open(supervisor_log) as f:
            invocations = [line.strip() for line in f if line.strip()]
        assert "-c /home/user/supervisord.conf restart all" in invocations, \
            f"Hook used the wrong supervisorctl arguments: {invocations}"

    assert_services_running()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
