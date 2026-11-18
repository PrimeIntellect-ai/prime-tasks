#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import secrets
import socket
import subprocess
import tempfile
import time


def test_profile_file():
    profile_path = "/home/user/.microservice_profile"
    assert os.path.isfile(profile_path), f"Profile file missing at {profile_path}"
    with open(profile_path, "r") as f:
        content = f.read()
    assert "export DEPLOY_ENV=staging" in content, "DEPLOY_ENV export missing or incorrect"
    assert "export TARGET_PORT=8080" in content, "TARGET_PORT export missing or incorrect"
    assert "export LOG_DIR=/home/user/logs" in content, "LOG_DIR export missing or incorrect"


def test_deployer_source_and_binary():
    source_path = "/home/user/src/deployer.go"
    bin_path = "/home/user/bin/deployer"
    assert os.path.isfile(source_path), f"Go source missing at {source_path}"
    assert os.path.isfile(bin_path), f"Deployer binary missing at {bin_path}"
    assert os.access(bin_path, os.X_OK), "Deployer binary is not executable"

    result = subprocess.run(
        ["go", "build", "-o", "/tmp/deployer-from-source", source_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, f"deployer.go does not compile: {result.stderr}"
    assert os.path.isfile("/tmp/deployer-from-source")
    assert os.access("/tmp/deployer-from-source", os.X_OK)


def test_git_repo_and_hook():
    repo_path = "/home/user/microservice.git"
    assert os.path.isdir(repo_path), f"Git repo directory missing at {repo_path}"
    assert os.path.isfile(os.path.join(repo_path, "config")), "Not a valid git repository"

    with open(os.path.join(repo_path, "config"), "r") as f:
        assert "bare = true" in f.read().lower(), "Git repository is not bare"

    hook_path = os.path.join(repo_path, "hooks/post-receive")
    assert os.path.isfile(hook_path), f"post-receive hook missing at {hook_path}"
    assert os.access(hook_path, os.X_OK), "post-receive hook is not executable"

    with open(hook_path, "r") as f:
        content = f.read()
    assert ".microservice_profile" in content, "Hook does not source the profile"
    assert "/home/user/bin/deployer" in content, "Hook does not execute the deployer"


def test_logrotate_conf():
    conf_path = "/home/user/logrotate.conf"
    assert os.path.isfile(conf_path), f"logrotate.conf missing at {conf_path}"
    with open(conf_path, "r") as f:
        content = f.read()
    assert "/home/user/logs/deploy.log" in content, "logrotate.conf does not target deploy.log"
    assert "daily" in content, "logrotate.conf missing 'daily' directive"
    assert "rotate 3" in content, "logrotate.conf missing 'rotate 3' directive"
    assert "compress" in content, "logrotate.conf missing 'compress' directive"
    assert "missingok" in content, "logrotate.conf missing 'missingok' directive"


def test_deploy_log_success():
    log_path = "/home/user/logs/deploy.log"
    assert os.path.isfile(log_path), f"Deploy log missing at {log_path}. Did you push a dummy commit?"
    with open(log_path, "r") as f:
        content = f.read()

    pattern = r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2}) DEPLOYMENT SUCCESSFUL: Env=staging, Port=8080$"
    match = re.search(pattern, content, re.MULTILINE)
    assert match is not None, "Deploy log does not contain the correctly formatted success message"


def wait_for_port(expect_open, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(0.2)
        try:
            sock.connect(("127.0.0.1", 9090))
            is_open = True
        except OSError:
            is_open = False
        finally:
            sock.close()
        if is_open == expect_open:
            return
        time.sleep(0.1)
    raise AssertionError(f"Port 9090 did not become {'open' if expect_open else 'closed'}")


def parse_and_check_timestamp(value, started, ended):
    parsed = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
    stamp = parsed.timestamp()
    assert started - 2 <= stamp <= ended + 2, "Log timestamp was not generated during this invocation"


def run_and_check(binary, log_dir, deploy_env, target_port, success):
    os.makedirs(log_dir, exist_ok=True)
    log_path = os.path.join(log_dir, "deploy.log")
    before = b""
    if os.path.exists(log_path):
        with open(log_path, "rb") as f:
            before = f.read()

    env = os.environ.copy()
    env.update({"DEPLOY_ENV": deploy_env, "TARGET_PORT": target_port, "LOG_DIR": log_dir})
    started = time.time()
    result = subprocess.run(
        [binary], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=6
    )
    ended = time.time()

    if success:
        assert result.returncode == 0, f"Deployer failed despite reachable dependency: {result.stderr!r}"
        message = rf"(?P<ts>\d{{4}}-\d{{2}}-\d{{2}}T\d{{2}}:\d{{2}}:\d{{2}}(?:Z|[+-]\d{{2}}:\d{{2}})) DEPLOYMENT SUCCESSFUL: Env={re.escape(deploy_env)}, Port={re.escape(target_port)}\n"
    else:
        assert result.returncode == 1, f"Deployer must exit with status 1 when dependency is unreachable, got {result.returncode}"
        message = r"(?P<ts>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:\d{2})) DEPLOYMENT FAILED: Dependency unreachable\n"

    assert os.path.isfile(log_path), "Deployer did not create deploy.log in LOG_DIR"
    with open(log_path, "rb") as f:
        after = f.read()
    assert after.startswith(before), "Deployer did not append to the existing log"
    appended = after[len(before):].decode("utf-8")
    match = re.fullmatch(message, appended)
    assert match is not None, f"Unexpected log data appended: {appended!r}"
    parse_and_check_timestamp(match.group("ts"), started, ended)


def test_live_deployer_hook_failure_and_logrotate():
    # Replace the image's mock service with a listener controlled by this test.
    subprocess.run(["fuser", "-k", "9090/tcp"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wait_for_port(False, timeout=3)
    except AssertionError:
        subprocess.run(["fuser", "-k", "9090/tcp"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    server_code = '''
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 9090))
s.listen(20)
while True:
    c, _ = s.accept()
    c.close()
'''
    server = subprocess.Popen(["python3", "-c", server_code], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    profile_path = "/home/user/.microservice_profile"
    with open(profile_path, "r") as f:
        original_profile = f.read()

    temp_root = tempfile.mkdtemp(prefix="deployer-verifier-")
    try:
        wait_for_port(True)
        assert server.poll() is None, "Controlled dependency service failed to start"

        # Exercise both the installed artifact and a fresh build of the submitted Go source.
        for binary in ("/home/user/bin/deployer", "/tmp/deployer-from-source"):
            token = secrets.token_hex(6)
            run_and_check(
                binary,
                os.path.join(temp_root, "direct-" + token),
                "verify-" + token,
                str(10000 + secrets.randbelow(50000)),
                True,
            )

        # Prove that a real Git push runs the hook, that the hook sources the profile,
        # and that the deployer uses the profile-provided environment.
        hook_token = secrets.token_hex(6)
        hook_env = "hook-" + hook_token
        hook_port = str(10000 + secrets.randbelow(50000))
        hook_log_dir = os.path.join(temp_root, "hook-" + hook_token)
        os.makedirs(hook_log_dir)
        with open(profile_path, "w") as f:
            f.write(
                f"export DEPLOY_ENV={hook_env}\n"
                f"export TARGET_PORT={hook_port}\n"
                f"export LOG_DIR={hook_log_dir}\n"
            )

        clone_dir = os.path.join(temp_root, "git-work")
        subprocess.run(["git", "init", clone_dir], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["git", "-C", clone_dir, "config", "user.name", "Verifier"], check=True)
        subprocess.run(["git", "-C", clone_dir, "config", "user.email", "verifier@example.invalid"], check=True)
        with open(os.path.join(clone_dir, "dummy.txt"), "w") as f:
            f.write(hook_token + "\n")
        subprocess.run(["git", "-C", clone_dir, "add", "dummy.txt"], check=True)
        subprocess.run(["git", "-C", clone_dir, "commit", "-m", "verifier dummy commit"], check=True, stdout=subprocess.DEVNULL)
        branch = "verify-" + hook_token
        started = time.time()
        pushed = subprocess.run(
            ["git", "-c", "safe.directory=*", "-C", clone_dir, "push", "/home/user/microservice.git", f"HEAD:refs/heads/{branch}"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        ended = time.time()
        assert pushed.returncode == 0, f"Push or post-receive hook failed: {pushed.stderr}"
        hook_log = os.path.join(hook_log_dir, "deploy.log")
        assert os.path.isfile(hook_log), "A real push did not cause the hook to create deploy.log"
        with open(hook_log, "r") as f:
            hook_data = f.read()
        hook_pattern = rf"(?P<ts>\d{{4}}-\d{{2}}-\d{{2}}T\d{{2}}:\d{{2}}:\d{{2}}(?:Z|[+-]\d{{2}}:\d{{2}})) DEPLOYMENT SUCCESSFUL: Env={re.escape(hook_env)}, Port={re.escape(hook_port)}\n"
        hook_match = re.fullmatch(hook_pattern, hook_data)
        assert hook_match is not None, f"Hook produced unexpected log data: {hook_data!r}"
        parse_and_check_timestamp(hook_match.group("ts"), started, ended)
    finally:
        with open(profile_path, "w") as f:
            f.write(original_profile)
        if server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait()
        subprocess.run(["fuser", "-k", "9090/tcp"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    wait_for_port(False)

    # Exercise failure behavior for both the installed binary and rebuilt source.
    for binary in ("/home/user/bin/deployer", "/tmp/deployer-from-source"):
        token = secrets.token_hex(6)
        run_and_check(
            binary,
            os.path.join(temp_root, "failure-" + token),
            "failure-" + token,
            str(10000 + secrets.randbelow(50000)),
            False,
        )

    # Preserve the original profile-driven failure assertion against the required log.
    log_path = "/home/user/logs/deploy.log"
    before_size = os.path.getsize(log_path) if os.path.exists(log_path) else 0
    result = subprocess.run(
        "source /home/user/.microservice_profile && /home/user/bin/deployer",
        shell=True,
        executable="/bin/bash",
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=6,
    )
    assert result.returncode == 1, "Profile-driven deployer did not exit with status 1"
    assert os.path.isfile(log_path), "Deploy log missing after failure test"
    with open(log_path, "r") as f:
        content = f.read()
    assert "DEPLOYMENT FAILED: Dependency unreachable" in content, "Deploy log does not contain the failure message after 9090 is killed"
    assert os.path.getsize(log_path) > before_size, "Failure invocation did not append to deploy.log"

    subprocess.run(
        ["logrotate", "-s", "/home/user/logrotate.status", "/home/user/logrotate.conf", "--force"],
        check=True,
    )
    rotated_log = "/home/user/logs/deploy.log.1.gz"
    assert os.path.isfile(rotated_log), f"Rotated log file missing at {rotated_log}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
