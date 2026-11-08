#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import ssl
import stat
import subprocess
import tempfile
import time
import urllib.request


def run(cmd, **kwargs):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kwargs)


def fetch_json(path):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    url = "https://localhost:8443" + path
    try:
        with urllib.request.urlopen(url, context=ctx, timeout=5) as response:
            return json.loads(response.read().decode("utf-8"))
    except Exception as exc:
        assert False, f"Failed to retrieve {url} via HTTPS: {exc}"


def shell_environment(source_env=False):
    command = "source /home/user/deploy_env.sh; env -0" if source_env else "env -0"
    result = subprocess.run(
        ["env", "-i", "/bin/bash", "--noprofile", "--norc", "-c", command],
        check=True,
        capture_output=True,
    )
    values = {}
    for entry in result.stdout.split(b"\0"):
        if b"=" in entry:
            key, value = entry.split(b"=", 1)
            values[key.decode()] = value.decode()
    return values


def test_server_running():
    pid_file = "/home/user/server.pid"
    assert os.path.exists(pid_file), "PID file /home/user/server.pid does not exist."

    with open(pid_file, "r") as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), "PID file does not contain a valid numeric PID."
    pid = int(pid_str)

    try:
        os.kill(pid, 0)
    except OSError:
        assert False, f"Process with PID {pid} is not running."

    assert os.path.isfile("/home/user/server.py"), "/home/user/server.py does not exist."
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
    assert "server.py" in cmdline, f"PID {pid} is not running server.py: {cmdline}"

    assert os.path.isfile("/home/user/cert.pem"), "/home/user/cert.pem does not exist."
    assert os.path.isfile("/home/user/key.pem"), "/home/user/key.pem does not exist."
    run(["openssl", "x509", "-in", "/home/user/cert.pem", "-noout", "-checkhost", "localhost"])
    run(["openssl", "verify", "-CAfile", "/home/user/cert.pem", "/home/user/cert.pem"])
    cert_pub = run(["openssl", "x509", "-in", "/home/user/cert.pem", "-pubkey", "-noout"]).stdout
    key_pub = run(["openssl", "pkey", "-in", "/home/user/key.pem", "-pubout"]).stdout
    assert cert_pub == key_pub, "The TLS certificate and private key do not match."


def test_pipeline_files():
    hook = "/home/user/dashboards.git/hooks/post-receive"
    assert os.path.isfile(hook), f"Git hook {hook} does not exist."
    assert stat.S_IMODE(os.stat(hook).st_mode) & 0o111, f"Git hook {hook} is not executable."
    assert os.path.isfile("/home/user/deploy_env.sh"), "/home/user/deploy_env.sh does not exist."
    assert os.path.isfile("/home/user/deploy.py"), "/home/user/deploy.py does not exist."

    baseline = shell_environment(False)
    loaded = shell_environment(True)
    assert loaded.get("DEPLOY_ENV") == "prod", "deploy_env.sh does not export DEPLOY_ENV=prod."
    for key in set(baseline) | set(loaded):
        if key not in {"DEPLOY_ENV", "_"}:
            assert baseline.get(key) == loaded.get(key), f"deploy_env.sh unexpectedly changes exported variable {key}."

    run(["python3", "-m", "py_compile", "/home/user/deploy.py", "/home/user/server.py"])


def test_git_repo_and_deployment():
    repo_path = "/home/user/dashboards.git"
    assert os.path.isdir(repo_path), f"Bare git repository {repo_path} does not exist."

    result = subprocess.run(
        ["git", "-C", repo_path, "rev-parse", "--is-bare-repository"],
        capture_output=True,
        text=True,
    )
    assert result.stdout.strip() == "true", f"Repository {repo_path} is not a bare repository."

    nonce = secrets.token_hex(16)
    first_name = f"dashboard_{nonce}.json"
    first_content = {"nonce": nonce, "count": secrets.randbelow(1000000)}

    with tempfile.TemporaryDirectory() as tmpdir:
        subprocess.run(["git", "clone", repo_path, tmpdir], check=True, capture_output=True)
        subprocess.run(["git", "-C", tmpdir, "config", "user.email", "test@example.com"], check=True, capture_output=True)
        subprocess.run(["git", "-C", tmpdir, "config", "user.name", "Test User"], check=True, capture_output=True)

        with open(os.path.join(tmpdir, "test_dash.json"), "w") as f:
            json.dump({"status": "ok"}, f)
        with open(os.path.join(tmpdir, first_name), "w") as f:
            json.dump(first_content, f)

        subprocess.run(["git", "-C", tmpdir, "add", "test_dash.json", first_name], check=True, capture_output=True)
        subprocess.run(["git", "-C", tmpdir, "commit", "-m", "Test dashboard"], check=True, capture_output=True)
        first_rev = run(["git", "-C", tmpdir, "rev-parse", "HEAD"]).stdout.strip()

        push_result = subprocess.run(["git", "-C", tmpdir, "push", "origin", "master"], capture_output=True, text=True)
        assert push_result.returncode == 0, f"Failed to push to bare repository: {push_result.stderr}"
        time.sleep(2)

        data = fetch_json("/dashboards/test_dash.json")
        assert data.get("status") == "ok", f"Expected {{'status': 'ok'}}, got {data}"
        assert fetch_json(f"/dashboards/{first_name}") == first_content

        # Exercise deploy.py itself against a verifier-selected commit.
        deployed_fixed = "/home/user/www/dashboards/test_dash.json"
        with open(deployed_fixed, "w") as f:
            json.dump({"status": "tampered"}, f)
        direct = subprocess.run(
            ["python3", "/home/user/deploy.py", first_rev],
            capture_output=True,
            text=True,
        )
        assert direct.returncode == 0, f"deploy.py failed: {direct.stderr}"
        with open(deployed_fixed) as f:
            assert json.load(f).get("status") == "ok", "deploy.py did not extract the requested commit."

        # Instrument deploy.py, then push another unpredictable commit. This verifies
        # that post-receive invokes that exact script and passes the pushed newrev.
        second_nonce = secrets.token_hex(20)
        second_name = f"dashboard_{second_nonce}.json"
        second_content = {"token": second_nonce, "enabled": bool(secrets.randbits(1))}
        with open(os.path.join(tmpdir, second_name), "w") as f:
            json.dump(second_content, f)
        subprocess.run(["git", "-C", tmpdir, "add", second_name], check=True, capture_output=True)
        subprocess.run(["git", "-C", tmpdir, "commit", "-m", "Second dashboard"], check=True, capture_output=True)
        second_rev = run(["git", "-C", tmpdir, "rev-parse", "HEAD"]).stdout.strip()

        deploy = "/home/user/deploy.py"
        real_deploy = "/home/user/deploy.py.verifier-real"
        call_log = f"/tmp/deploy-call-{secrets.token_hex(12)}"
        os.replace(deploy, real_deploy)
        try:
            wrapper = f'''#!/usr/bin/env python3
import os, sys
with open({call_log!r}, "a") as log:
    log.write((sys.argv[1] if len(sys.argv) > 1 else "") + "\\n")
os.execv(sys.executable, [sys.executable, {real_deploy!r}] + sys.argv[1:])
'''
            with open(deploy, "w") as f:
                f.write(wrapper)
            os.chmod(deploy, 0o755)

            push_result = subprocess.run(["git", "-C", tmpdir, "push", "origin", "master"], capture_output=True, text=True)
            assert push_result.returncode == 0, f"Second push failed: {push_result.stderr}"
            time.sleep(2)

            assert os.path.exists(call_log), "post-receive did not invoke /home/user/deploy.py."
            with open(call_log) as f:
                calls = [line.strip() for line in f if line.strip()]
            assert calls and calls[-1] == second_rev, "post-receive did not pass newrev to deploy.py."
            assert fetch_json(f"/dashboards/{second_name}") == second_content
            assert fetch_json("/dashboards/test_dash.json").get("status") == "ok"
        finally:
            if os.path.exists(real_deploy):
                os.replace(real_deploy, deploy)
            if os.path.exists(call_log):
                os.unlink(call_log)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
