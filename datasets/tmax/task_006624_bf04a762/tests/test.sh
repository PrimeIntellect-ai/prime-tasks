#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import socket
import stat
import subprocess
import tempfile
import time
import uuid
from datetime import datetime
from zoneinfo import ZoneInfo

WORKSPACE = "/home/user/workspace"
BARE_REPO = "/home/user/repo/netmon.git"
DEPLOY = "/home/user/deploy"
LOGS = "/home/user/logs"
HOOK = BARE_REPO + "/hooks/post-receive"


def run(cmd, **kwargs):
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("text", True)
    kwargs.setdefault("timeout", 30)
    result = subprocess.run(cmd, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {cmd}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def workspace_git(*args):
    return run(["git", "-c", f"safe.directory={WORKSPACE}", "-C", WORKSPACE, *args])


def bare_git(*args):
    return run(["git", "-c", f"safe.directory={BARE_REPO}", f"--git-dir={BARE_REPO}", *args])


def test_deploy_and_logs_directories_exist():
    assert os.path.isdir(DEPLOY), f"Deployment directory {DEPLOY} does not exist."
    assert os.path.isdir(LOGS), f"Logs directory {LOGS} does not exist."


def test_post_receive_hook_exists_and_executable():
    assert os.path.isfile(HOOK), f"Git hook {HOOK} does not exist."
    st = os.stat(HOOK)
    assert bool(st.st_mode & stat.S_IXUSR), f"Git hook {HOOK} is not executable."


def test_monitor_compiled_and_executable():
    monitor_bin = DEPLOY + "/monitor"
    assert os.path.isfile(monitor_bin), f"Compiled binary {monitor_bin} does not exist."
    st = os.stat(monitor_bin)
    assert bool(st.st_mode & stat.S_IXUSR), f"Compiled binary {monitor_bin} is not executable."


def test_net_log_exists_and_contains_jst():
    log_path = LOGS + "/net.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."
    with open(log_path, "r") as f:
        content = f.read()
    assert "JST" in content, f"Log file {log_path} does not contain the JST timezone identifier."
    assert "Port 8080" in content, f"Log file {log_path} does not contain 'Port 8080'."


def test_monitor_c_fixed_compiles_cleanly_and_was_pushed():
    workspace_monitor = WORKSPACE + "/monitor.c"
    assert os.path.isfile(workspace_monitor), f"Source file {workspace_monitor} does not exist."
    with open(workspace_monitor, "r") as f:
        content = f.read()

    # Preserve the original header assertion, then require all declarations used by the program.
    assert ("<sys/socket.h>" in content or "<arpa/inet.h>" in content or
            "<netinet/in.h>" in content), "The required network headers were not added to monitor.c."
    for header in ("<sys/socket.h>", "<netinet/in.h>", "<arpa/inet.h>"):
        assert header in content, f"monitor.c is missing required header {header}."

    status = workspace_git("status", "--porcelain")
    assert status.stdout.strip() == "", "There are uncommitted changes in the workspace."

    head = workspace_git("rev-parse", "HEAD").stdout.strip()
    bare_master = bare_git("rev-parse", "refs/heads/master").stdout.strip()
    assert head == bare_master, "The workspace HEAD was not pushed to the bare repository's master branch."

    remote_master = workspace_git("rev-parse", "refs/remotes/origin/master").stdout.strip()
    assert head == remote_master, "The workspace and origin/master are not at the same commit."

    message = workspace_git("log", "-1", "--format=%B").stdout.strip()
    assert message == "Fix headers", f"Latest commit message is {message!r}, not 'Fix headers'."

    with tempfile.TemporaryDirectory() as td:
        output = os.path.join(td, "monitor")
        result = subprocess.run(
            ["gcc", "-Wall", "-Wextra", "-Werror", workspace_monitor, "-o", output],
            capture_output=True, text=True, timeout=30
        )
        assert result.returncode == 0, (
            "monitor.c does not compile cleanly with warnings treated as errors:\n"
            + result.stdout + result.stderr
        )
        assert os.path.isfile(output) and os.access(output, os.X_OK)


def test_zz_hook_really_deploys_compiles_executes_and_sets_tz():
    nonce = uuid.uuid4().hex
    probe_path = f"{LOGS}/hook_probe_{nonce}.log"
    temp_clone = tempfile.mkdtemp(prefix="netmon-verifier-")

    try:
        run([
            "git", "-c", f"safe.directory={BARE_REPO}", "clone",
            BARE_REPO, temp_clone
        ])
        run(["git", "-C", temp_clone, "config", "user.email", "verifier@example.invalid"])
        run(["git", "-C", temp_clone, "config", "user.name", "Verifier"])

        # Add a unique constructor to the pushed source. Its output proves that the hook
        # checked out this exact revision, compiled it, executed it, and supplied TZ.
        source_path = os.path.join(temp_clone, "monitor.c")
        with open(source_path, "a") as f:
            f.write(f'''\n\n__attribute__((constructor))\nstatic void verifier_probe_{nonce}(void) {{\n    FILE *vf = fopen("{probe_path}", "a");\n    if (vf) {{\n        const char *tz = getenv("TZ");\n        fprintf(vf, "{nonce}:%s\\n", tz ? tz : "");\n        fclose(vf);\n    }}\n}}\n''')

        marker_path = os.path.join(temp_clone, f"deployment-marker-{nonce}")
        with open(marker_path, "w") as f:
            f.write(nonce + "\n")

        run(["git", "-C", temp_clone, "add", "monitor.c", os.path.basename(marker_path)])
        run(["git", "-C", temp_clone, "commit", "-m", "Verifier deployment probe"])

        # Remove all pre-existing deployment artifacts and logs so only this push can
        # satisfy the behavioral checks.
        shutil.rmtree(DEPLOY)
        os.makedirs(DEPLOY)
        with open(LOGS + "/net.log", "w"):
            pass
        if os.path.exists(probe_path):
            os.unlink(probe_path)

        env = os.environ.copy()
        env["TZ"] = "UTC"  # The hook must override this for monitor itself.
        before_push = time.time()
        push = subprocess.run(
            ["git", "-C", temp_clone, "push", "origin", "master"],
            capture_output=True, text=True, timeout=60, env=env
        )
        after_push = time.time()
        assert push.returncode == 0, (
            f"Probe push failed; the post-receive hook may have failed.\n"
            f"stdout:\n{push.stdout}\nstderr:\n{push.stderr}"
        )

        deployed_marker = os.path.join(DEPLOY, os.path.basename(marker_path))
        assert os.path.isfile(deployed_marker), "The hook did not check out the latest master revision."
        with open(deployed_marker) as f:
            assert f.read().strip() == nonce

        deployed_source = DEPLOY + "/monitor.c"
        assert os.path.isfile(deployed_source), "The hook did not deploy monitor.c."
        expected_source = bare_git("show", "master:monitor.c").stdout
        with open(deployed_source) as f:
            assert f.read() == expected_source, "Deployed monitor.c is not the latest master version."

        monitor_bin = DEPLOY + "/monitor"
        assert os.path.isfile(monitor_bin) and os.access(monitor_bin, os.X_OK), \
            "The hook did not create an executable monitor binary."
        with open(monitor_bin, "rb") as f:
            assert f.read(4) == b"\x7fELF", "The deployed monitor is not a compiled ELF executable."

        assert os.path.isfile(probe_path), "The monitor built from the pushed source was not executed by the hook."
        with open(probe_path) as f:
            probe = f.read().splitlines()
        assert f"{nonce}:Asia/Tokyo" in probe, \
            "The hook did not execute monitor with TZ set exactly to Asia/Tokyo."

        with open(LOGS + "/net.log") as f:
            lines = f.read().splitlines()
        pattern = re.compile(
            r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) JST\] Port 8080: (SUCCESS|FAILURE)$"
        )
        matches = [pattern.match(line) for line in lines]
        matches = [m for m in matches if m]
        assert matches, "The hook execution did not append a valid JST log entry for port 8080."
        logged_local = datetime.strptime(matches[-1].group(1), "%Y-%m-%d %H:%M:%S")
        logged_epoch = logged_local.replace(tzinfo=ZoneInfo("Asia/Tokyo")).timestamp()
        assert before_push - 5 <= logged_epoch <= after_push + 5, \
            "The JST log entry was not generated during the verification push."

        # Exercise the resulting artifact on a verifier-selected open port and derive
        # the expected SUCCESS result from a real listening socket.
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        port = listener.getsockname()[1]
        old_size = os.path.getsize(LOGS + "/net.log")
        direct_env = os.environ.copy()
        direct_env["TZ"] = "UTC"
        direct = subprocess.run([monitor_bin, str(port)], env=direct_env,
                                capture_output=True, text=True, timeout=15)
        listener.close()
        assert direct.returncode == 0, "The deployed monitor executable failed when run."
        with open(LOGS + "/net.log") as f:
            f.seek(old_size)
            appended = f.read()
        assert re.search(rf"Port {port}: SUCCESS", appended), \
            "The deployed monitor did not correctly detect a verifier-created listening port."
    finally:
        shutil.rmtree(temp_clone, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
