#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import gzip
import os
import re
import shutil
import stat
import subprocess
import tempfile
import time

C_FILE = "/home/user/src/net_monitor.c"
REPO = "/home/user/git/capacity.git"
HOOK = REPO + "/hooks/post-receive"
SCRIPT = "/home/user/simulate_push.exp"
LOG = "/home/user/logs/net_stats.log"
LINE_RE = re.compile(r"^Network stats recorded at ([0-9]+)$")


def run(cmd, **kwargs):
    kwargs.setdefault("text", True)
    kwargs.setdefault("capture_output", True)
    kwargs.setdefault("timeout", 30)
    result = subprocess.run(cmd, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {cmd}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def git_env():
    env = os.environ.copy()
    env.update({
        "GIT_CONFIG_COUNT": "3",
        "GIT_CONFIG_KEY_0": "safe.directory",
        "GIT_CONFIG_VALUE_0": "*",
        "GIT_CONFIG_KEY_1": "user.name",
        "GIT_CONFIG_VALUE_1": "Verifier User",
        "GIT_CONFIG_KEY_2": "user.email",
        "GIT_CONFIG_VALUE_2": "verifier@example.invalid",
    })
    return env


def valid_log_lines(path=LOG):
    assert os.path.isfile(path), f"Log file {path} was not generated"
    with open(path, encoding="utf-8") as f:
        lines = [line.rstrip("\n") for line in f]
    assert lines, f"Log file {path} is empty"
    for line in lines:
        match = LINE_RE.fullmatch(line)
        assert match, f"Unexpected log line: {line!r}"
        timestamp = int(match.group(1))
        assert abs(time.time() - timestamp) < 300, f"Log timestamp is not recent: {timestamp}"
    return lines


def test_c_program_modified_and_behaves_correctly():
    assert os.path.isfile(C_FILE), f"{C_FILE} is missing"
    with open(C_FILE, "r") as f:
        content = f.read()
    assert 'getenv("LOG_DIR")' in content, 'net_monitor.c does not use getenv("LOG_DIR")'
    assert '/tmp/net_stats.log' in content, "net_monitor.c does not contain the default fallback path /tmp/net_stats.log"

    with tempfile.TemporaryDirectory() as td:
        executable = os.path.join(td, "net_monitor")
        run(["gcc", C_FILE, "-o", executable])

        selected_dir = os.path.join(td, "selected")
        os.mkdir(selected_dir)
        env = os.environ.copy()
        env["LOG_DIR"] = selected_dir
        run([executable], env=env, cwd=td)
        selected_log = os.path.join(selected_dir, "net_stats.log")
        valid_log_lines(selected_log)
        assert not os.path.exists(os.path.join(td, "net_stats.log")), "Program still writes relative to its working directory"

        default_log = "/tmp/net_stats.log"
        if os.path.exists(default_log):
            os.remove(default_log)
        env.pop("LOG_DIR", None)
        run([executable], env=env, cwd=td)
        valid_log_lines(default_log)
        assert not os.path.exists(os.path.join(td, "net_stats.log")), "Unset LOG_DIR writes to the working directory instead of /tmp"
        os.remove(default_log)


def test_directories_exist():
    for d in ["/home/user/logs", "/home/user/bin"]:
        assert os.path.isdir(d), f"Directory {d} does not exist"


def test_bare_git_repo():
    assert os.path.isdir(REPO), f"Bare repository directory {REPO} does not exist"
    assert os.path.isfile(os.path.join(REPO, "HEAD")), "Git HEAD file missing, not a valid bare repo"
    config_file = os.path.join(REPO, "config")
    assert os.path.isfile(config_file), "Git config file missing"
    with open(config_file, "r") as f:
        content = f.read()
    assert "bare = true" in content, "Repository is not configured as bare"
    result = run(["git", "--git-dir", REPO, "rev-parse", "--is-bare-repository"], env=git_env())
    assert result.stdout.strip() == "true", "Repository is not a functioning bare Git repository"


def test_git_hook():
    assert os.path.isfile(HOOK), f"Hook file {HOOK} is missing"
    st = os.stat(HOOK)
    assert bool(st.st_mode & stat.S_IXUSR), f"Hook file {HOOK} is not executable"
    with open(HOOK, "r") as f:
        content = f.read()
    assert "LOG_DIR=/home/user/logs" in content, "Hook does not export LOG_DIR correctly"
    assert "/home/user/bin/net_monitor" in content, "Hook does not execute the compiled binary"
    assert "gcc" in content or "cc" in content or "make" in content, "Hook does not seem to compile the C program"


def test_expect_script_and_complete_push_workflow():
    assert os.path.isfile(SCRIPT), f"Expect script {SCRIPT} is missing"
    st = os.stat(SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Expect script {SCRIPT} is not executable"
    with open(SCRIPT, "r") as f:
        content = f.read()
    assert "git clone" in content, "Expect script missing git clone command"
    assert "trigger.txt" in content, "Expect script does not create trigger.txt"
    assert "git push" in content, "Expect script missing git push command"

    # Restore an empty-repository starting condition so the required empty-file
    # commit can be exercised even though the agent was required to run it once.
    refs = run(["git", "--git-dir", REPO, "for-each-ref", "--format=%(refname)"], env=git_env()).stdout.splitlines()
    for ref in refs:
        run(["git", "--git-dir", REPO, "update-ref", "-d", ref], env=git_env())

    shutil.rmtree("/home/user/capacity_clone", ignore_errors=True)
    for path in glob.glob("/home/user/logs/net_stats.log*"):
        if os.path.isfile(path) or os.path.islink(path):
            os.remove(path)
    if os.path.exists("/home/user/bin/net_monitor"):
        os.remove("/home/user/bin/net_monitor")

    run(["/usr/bin/expect", "-f", SCRIPT], env=git_env(), timeout=60)

    clone = "/home/user/capacity_clone"
    assert os.path.isdir(os.path.join(clone, ".git")), "Expect script did not create a real Git clone"
    assert os.path.isfile(os.path.join(clone, "trigger.txt")), "Expect script did not create trigger.txt"
    message = run(["git", "-C", clone, "log", "-1", "--format=%s"], env=git_env()).stdout.strip()
    assert message == "Trigger network monitor", f"Unexpected commit message: {message!r}"
    tree = run(["git", "--git-dir", REPO, "ls-tree", "-r", "--name-only", "HEAD"], env=git_env()).stdout.splitlines()
    assert "trigger.txt" in tree, "The trigger commit was not pushed to the bare repository"
    first_lines = valid_log_lines()

    binary = "/home/user/bin/net_monitor"
    assert os.path.isfile(binary), "The hook did not compile /home/user/bin/net_monitor"
    assert os.access(binary, os.X_OK), "Compiled net_monitor is not executable"
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Hook output is not a compiled ELF executable"

    # Perform another real push independently. Removing the binary proves the
    # post-receive hook recompiles it, and the new log line proves it executes it.
    os.remove(binary)
    marker = os.path.join(clone, "verifier_hook_trigger.txt")
    with open(marker, "w") as f:
        f.write(str(time.time()))
    run(["git", "-C", clone, "add", "verifier_hook_trigger.txt"], env=git_env())
    run(["git", "-C", clone, "commit", "-m", "Verifier hook trigger"], env=git_env())
    run(["git", "-C", clone, "push", "origin", "HEAD"], env=git_env(), timeout=60)

    assert os.path.isfile(binary) and os.access(binary, os.X_OK), "Hook did not recompile the program on push"
    later_lines = valid_log_lines()
    assert len(later_lines) > len(first_lines), "A real push did not cause the hook to append a network-stat log entry"

    with tempfile.TemporaryDirectory() as td:
        env = os.environ.copy()
        env["LOG_DIR"] = td
        run([binary], env=env)
        valid_log_lines(os.path.join(td, "net_stats.log"))


def test_log_file_generated():
    assert os.path.isfile(LOG), f"Log file {LOG} was not generated. Did the Expect script run successfully?"
    with open(LOG, "r") as f:
        content = f.read()
    assert "Network stats recorded at" in content, "Log file does not contain the expected output string"
    valid_log_lines()


def test_logrotate_config_and_behavior():
    conf_file = "/home/user/logrotate.conf"
    assert os.path.isfile(conf_file), f"Logrotate config {conf_file} is missing"
    with open(conf_file, "r") as f:
        content = f.read()
    assert "/home/user/logs/net_stats.log" in content, "Logrotate config does not target the correct log file"
    assert "daily" in content, "Logrotate config missing 'daily'"
    assert "rotate 5" in content, "Logrotate config missing 'rotate 5'"
    assert "compress" in content, "Logrotate config missing 'compress'"
    assert "missingok" in content, "Logrotate config missing 'missingok'"

    for path in glob.glob(LOG + ".*"):
        if os.path.isfile(path) or os.path.islink(path):
            os.remove(path)
    home_mode = stat.S_IMODE(os.stat("/home/user").st_mode)
    logs_mode = stat.S_IMODE(os.stat("/home/user/logs").st_mode)
    state_file = "/tmp/verifier-logrotate.state"
    if os.path.exists(state_file):
        os.remove(state_file)
    try:
        # The setup intentionally made /home/user world-writable; temporarily
        # remove that unrelated logrotate safety obstacle while testing config.
        os.chmod("/home/user", 0o755)
        os.chmod("/home/user/logs", 0o755)
        run(["logrotate", "-f", "-s", state_file, conf_file])
    finally:
        os.chmod("/home/user/logs", logs_mode)
        os.chmod("/home/user", home_mode)

    rotated = [p for p in glob.glob(LOG + ".*") if os.path.isfile(p)]
    compressed = [p for p in rotated if p.endswith(".gz")]
    assert compressed, "Forcing logrotate did not create a compressed rotated log"
    with gzip.open(compressed[0], "rt") as f:
        rotated_content = f.read()
    assert "Network stats recorded at" in rotated_content, "Compressed rotation does not contain the network log"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
