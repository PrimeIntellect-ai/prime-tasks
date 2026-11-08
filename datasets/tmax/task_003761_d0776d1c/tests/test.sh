#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import secrets
import shutil
import stat
import string
import subprocess
import tempfile
import time
import urllib.parse
import urllib.request

import pytest

APP_REPO = "/home/user/app-config"
BARE_REPO = "/home/user/deploy.git"
DEPLOYED_CONF = "/home/user/nginx/nginx.conf"


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kwargs)


def test_nginx_conf_updated():
    path = os.path.join(APP_REPO, "nginx.conf")
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()
    assert "/tmp/app_backend_real.sock" in content, "nginx.conf does not point to the correct socket path."


def test_git_hook_setup():
    hook_path = os.path.join(BARE_REPO, "hooks/post-receive")
    assert os.path.isfile(hook_path), f"Git hook {hook_path} does not exist."
    assert os.access(hook_path, os.X_OK), f"Git hook {hook_path} is not executable."
    assert run(["git", "--git-dir", BARE_REPO, "rev-parse", "--is-bare-repository"]).stdout.strip() == "true"

    remotes = run(["git", "-C", APP_REPO, "remote"]).stdout.split()
    assert remotes, "app-config has no configured Git remote."
    points_to_deploy = False
    for remote in remotes:
        url = run(["git", "-C", APP_REPO, "remote", "get-url", "--push", remote]).stdout.strip()
        if url.startswith("file://"):
            candidate = urllib.parse.urlparse(url).path
        elif ":" not in url:
            candidate = url if os.path.isabs(url) else os.path.join(APP_REPO, url)
        else:
            continue
        if os.path.realpath(candidate) == os.path.realpath(BARE_REPO):
            points_to_deploy = True
            break
    assert points_to_deploy, "app-config is not configured to push to /home/user/deploy.git."

    branch = run(["git", "-C", APP_REPO, "rev-parse", "--abbrev-ref", "HEAD"]).stdout.strip()
    pushed_conf = run([
        "git", "--git-dir", BARE_REPO, "show", f"refs/heads/{branch}:nginx.conf"
    ]).stdout
    with open(os.path.join(APP_REPO, "nginx.conf")) as f:
        local_conf = f.read()
    assert pushed_conf == local_conf, "The current nginx.conf fix was not pushed to deploy.git."


def test_nginx_serving_backend():
    try:
        req = urllib.request.Request("http://127.0.0.1:8080")
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200, f"Expected status 200, got {response.status}"
    except urllib.error.HTTPError as e:
        pytest.fail(f"Nginx returned HTTP error: {e.code}")
    except Exception as e:
        pytest.fail(f"Failed to connect to Nginx: {e}")


def test_post_receive_actually_deploys_and_reloads():
    branch = run(["git", "-C", APP_REPO, "rev-parse", "--abbrev-ref", "HEAD"]).stdout.strip()
    marker = "verify-" + secrets.token_hex(12)

    with tempfile.TemporaryDirectory(prefix="verify-deploy-") as td:
        clone = os.path.join(td, "clone")
        run(["git", "clone", BARE_REPO, clone])
        run(["git", "-C", clone, "checkout", "-B", branch, f"origin/{branch}"])
        run(["git", "-C", clone, "config", "user.email", "verifier@example.invalid"])
        run(["git", "-C", clone, "config", "user.name", "Verifier"])

        conf_path = os.path.join(clone, "nginx.conf")
        with open(conf_path) as f:
            conf = f.read()
        needle = "location / {"
        assert needle in conf, "nginx.conf is missing its proxy location."
        conf = conf.replace(
            needle,
            needle + f'\n            add_header X-Deployment-Verification "{marker}" always;',
            1,
        )
        with open(conf_path, "w") as f:
            f.write(conf)
        run(["git", "-C", clone, "add", "nginx.conf"])
        run(["git", "-C", clone, "commit", "-m", "Verifier deployment probe"])
        run(["git", "-C", clone, "push", "origin", f"HEAD:refs/heads/{branch}"])

        assert os.path.isfile(DEPLOYED_CONF), "The hook did not create the deployed nginx.conf."
        with open(DEPLOYED_CONF) as f:
            deployed = f.read()
        assert deployed == conf, "The post-receive hook did not copy the pushed nginx.conf."

        last_error = None
        for _ in range(25):
            try:
                req = urllib.request.Request(
                    "http://127.0.0.1:8080/",
                    headers={"Cache-Control": "no-cache"},
                )
                with urllib.request.urlopen(req, timeout=2) as response:
                    if response.status == 200 and response.headers.get("X-Deployment-Verification") == marker:
                        return
            except Exception as exc:
                last_error = exc
            time.sleep(0.2)
        pytest.fail(f"Pushed configuration was not loaded by Nginx; last error: {last_error}")


def test_token_generator_fuzz_equivalence():
    oracle = "/app/token_generator"
    agent = "/home/user/token_generator.py"

    assert os.path.isfile(agent), f"Agent script {agent} does not exist."
    mode = os.stat(agent).st_mode
    assert mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH), "Agent script is not executable."
    with open(agent, "rb") as f:
        first_line = f.readline()
    assert first_line.startswith(b"#!") and b"python" in first_line.lower(), "Agent script lacks a Python shebang."

    chars = string.ascii_letters + string.digits
    cases = []
    for _ in range(200):
        length = secrets.randbelow(28) + 5
        value = "".join(secrets.choice(chars) for _ in range(length))
        derived = hashlib.sha256((value[::-1] + "SECRET_SALT_2024").encode()).hexdigest() + "\n"
        oracle_proc = run([oracle, value])
        assert oracle_proc.stdout == derived, "Verifier's independently derived token disagrees with the supplied binary."
        cases.append((value, derived))

    original_mode = stat.S_IMODE(os.stat(oracle).st_mode)
    os.chmod(oracle, 0o700)
    try:
        for value, expected in cases:
            try:
                agent_proc = run(["runuser", "-u", "user", "--", agent, value])
            except subprocess.CalledProcessError as e:
                pytest.fail(f"Agent script failed on input {value!r}: {e.stderr}")
            assert agent_proc.stderr == "", f"Agent script wrote to stderr on input {value!r}."
            assert agent_proc.stdout == expected, (
                f"Output mismatch on input {value!r}.\n"
                f"Expected output: {expected!r}\n"
                f"Agent output:    {agent_proc.stdout!r}"
            )
    finally:
        os.chmod(oracle, original_mode)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
