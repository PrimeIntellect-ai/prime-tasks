#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import http.client
import json
import os
import re
import signal
import socket
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

import pytest

REPO = "/home/user/dashboards.git"
HOOK = "/home/user/dashboards.git/hooks/pre-receive"
DEPLOY = "/home/user/deploy.sh"


def run(cmd, **kwargs):
    return subprocess.run(cmd, text=True, **kwargs)


def git(cwd, *args, check=True):
    return run(["git", "-C", cwd, *args], check=check,
               stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def commit_file(repo, name, value, message):
    path = Path(repo) / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value))
    git(repo, "add", name)
    git(repo, "commit", "-m", message)


def push(repo, local_ref, remote_ref):
    return git(repo, "push", "origin", f"{local_ref}:{remote_ref}", check=False)


def test_port_forwarding():
    """Port 8080 must carry an HTTP request to the supplied API on 9090."""
    marker = uuid.uuid4().hex.encode()
    log = Path("/app/uploaded.log")
    before = log.read_text().count("success\n") if log.exists() else 0

    conn = http.client.HTTPConnection("127.0.0.1", 8080, timeout=3)
    conn.request("POST", "/api/dashboard", body=marker,
                 headers={"Content-Type": "application/json"})
    response = conn.getresponse()
    response.read()
    conn.close()
    assert response.status == 200, "Port 8080 did not return the backend's HTTP response."

    deadline = time.time() + 3
    while time.time() < deadline:
        if log.exists() and log.read_text().count("success\n") > before:
            break
        time.sleep(0.1)
    else:
        pytest.fail("A request to port 8080 did not reach the API listening on 9090.")


def test_cron_configured():
    """deploy.sh must be scheduled every minute in the current user's crontab."""
    result = run(["crontab", "-l"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert result.returncode == 0, "No crontab configured for the current user."
    active = [line.strip() for line in result.stdout.splitlines()
              if line.strip() and not line.lstrip().startswith("#")]
    assert any(re.match(r"^\*\s+\*\s+\*\s+\*\s+\*\s+.*(?:^|\s)/home/user/deploy\.sh(?:\s|$)", line)
               for line in active), "deploy.sh is not scheduled to run every minute."


def test_required_artifacts():
    assert os.path.isdir(REPO), f"Bare repository {REPO} does not exist."
    bare = git(REPO, "rev-parse", "--is-bare-repository").stdout.strip()
    assert bare == "true", f"{REPO} is not a bare Git repository."

    hook = Path(HOOK)
    assert hook.is_file(), "The pre-receive hook does not exist."
    assert os.access(HOOK, os.X_OK), "The pre-receive hook is not executable."
    text = hook.read_text(errors="replace")
    first = text.splitlines()[0] if text.splitlines() else ""
    assert re.match(r"^#!.*(?:/bash|env\s+bash)(?:\s|$)", first), "The hook is not written in Bash."
    assert re.search(r"\bjq\b", text), "The hook does not use jq."
    assert re.search(r"git\s+cat-file\b", text), "The hook does not use git cat-file."

    deploy = Path(DEPLOY)
    assert deploy.is_file(), "deploy.sh does not exist."
    assert os.access(DEPLOY, os.X_OK), "deploy.sh is not executable."


def test_git_hook_general_rules_and_fixed_corpus():
    """Exercise randomized names and values, updates, batches, and new branches."""
    token = uuid.uuid4().hex
    with tempfile.TemporaryDirectory() as td:
        git(td, "init")
        git(td, "config", "user.name", "Verifier")
        git(td, "config", "user.email", "verifier@example.invalid")
        git(td, "remote", "add", "origin", REPO)

        commit_file(td, "base.json", {"nonce": token, "refresh_rate": "30s"}, "valid base")
        base = git(td, "rev-parse", "HEAD").stdout.strip()
        base_ref = f"refs/heads/verify-base-{token}"
        result = push(td, "HEAD", base_ref)
        assert result.returncode == 0, f"Hook rejected a valid new branch: {result.stderr}"

        fixed_evil = []
        for p in sorted(Path("/app/test_corpus/evil").glob("*.json")):
            fixed_evil.append((f"fixed evil {p.name}", json.loads(p.read_text()), False))
        fixed_clean = []
        for p in sorted(Path("/app/test_corpus/clean").glob("*.json")):
            fixed_clean.append((f"fixed clean {p.name}", json.loads(p.read_text()), True))

        cases = fixed_evil + fixed_clean + [
            ("random forbidden 1s", {"nonce": token, "refresh_rate": "1s"}, False),
            ("random forbidden 5s", {"refresh_rate": "5s", "other": uuid.uuid4().hex}, False),
            ("random forbidden 10s", {"refresh_rate": "10s", "datasource": "staging"}, False),
            ("production missing mode", {"datasource": "production", "nonce": token}, False),
            ("production wrong case", {"datasource": "production", "mode": "Read-Only"}, False),
            ("production null mode", {"datasource": "production", "mode": None}, False),
            ("production exact mode", {"datasource": "production", "mode": "read-only"}, True),
            ("nonproduction unrestricted mode", {"datasource": "development", "mode": "write"}, True),
            ("allowed arbitrary rate", {"refresh_rate": "17s", "nonce": token}, True),
            ("nested keys are not top-level", {"panel": {"refresh_rate": "1s", "datasource": "production", "mode": "write"}}, True),
            ("numeric rate is not forbidden string", {"refresh_rate": 5, "nonce": token}, True),
        ]

        for index, (label, obj, should_pass) in enumerate(cases):
            git(td, "checkout", "-B", f"case-{index}", base)
            name = f"nested dir/{token}-{index} dashboard.json"
            commit_file(td, name, obj, label)
            remote_ref = f"refs/heads/verify-{token}-{index}"
            result = push(td, "HEAD", remote_ref)
            if should_pass:
                assert result.returncode == 0, f"Hook rejected valid case '{label}': {result.stderr}"
            else:
                assert result.returncode != 0, f"Hook accepted invalid case '{label}'."

        # A single invalid JSON file must reject an otherwise-valid multi-file push.
        git(td, "checkout", "-B", "batch-case", base)
        commit_file(td, f"{token}-batch-good.json", {"refresh_rate": "45s"}, "batch good")
        commit_file(td, f"{token}-batch-bad.json", {"refresh_rate": "5s"}, "batch bad")
        result = push(td, "HEAD", f"refs/heads/verify-{token}-batch")
        assert result.returncode != 0, "Hook accepted a batch containing an invalid JSON file."

        # Validate an update to an existing branch, not just creation of new branches.
        update_ref = f"refs/heads/verify-{token}-update"
        git(td, "checkout", "-B", "update-case", base)
        commit_file(td, f"{token}-update.json", {"datasource": "production", "mode": "read-only"}, "valid update base")
        assert push(td, "HEAD", update_ref).returncode == 0
        commit_file(td, f"{token}-update.json", {"datasource": "production", "mode": "write"}, "invalid update")
        assert push(td, "HEAD", update_ref).returncode != 0, "Hook accepted an invalid modification."

        # Non-JSON files are ignored, and deleting a ref is handled gracefully.
        git(td, "checkout", "-B", "non-json-case", base)
        Path(td, f"{token}.txt").write_text('{"refresh_rate":"1s"}')
        git(td, "add", f"{token}.txt")
        git(td, "commit", "-m", "non-json content")
        nonjson_ref = f"refs/heads/verify-{token}-nonjson"
        assert push(td, "HEAD", nonjson_ref).returncode == 0, "Hook incorrectly inspected a non-JSON file."
        deleted = git(td, "push", "origin", f":{nonjson_ref}", check=False)
        assert deleted.returncode == 0, "Hook did not gracefully handle a ref deletion."


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if len(fields) > 9 and fields[3] == "0A":
                local_port = int(fields[1].rsplit(":", 1)[1], 16)
                if local_port == port:
                    inodes.add(fields[9])
    pids = set()
    for proc in Path("/proc").glob("[0-9]*"):
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(proc.name))
        except OSError:
            pass
    return pids


def test_deploy_script_posts_repository_json_through_forwarder():
    """Run deploy.sh and verify exact randomized bodies, endpoint, and content type."""
    token = uuid.uuid4().hex
    expected = [
        {"id": token, "refresh_rate": "31s", "datasource": "dev"},
        {"id": token[::-1], "datasource": "production", "mode": "read-only"},
    ]

    with tempfile.TemporaryDirectory() as source, tempfile.TemporaryDirectory() as capture_dir:
        git(source, "init")
        git(source, "config", "user.name", "Verifier")
        git(source, "config", "user.email", "verifier@example.invalid")
        git(source, "remote", "add", "origin", REPO)
        git(source, "checkout", "--orphan", f"deploy-{token}")
        for child in Path(source).iterdir():
            if child.name != ".git":
                if child.is_dir():
                    subprocess.check_call(["rm", "-rf", str(child)])
                else:
                    child.unlink()
        commit_file(source, "dashboards/first.json", expected[0], "deployment corpus")
        commit_file(source, "dashboards/nested/second dashboard.json", expected[1], "deployment corpus second")
        Path(source, "dashboards/ignore.txt").write_text(json.dumps({"id": "must-not-upload"}))
        git(source, "add", "dashboards/ignore.txt")
        git(source, "commit", "-m", "ignored non-json")
        branch = f"deploy-verify-{token}"
        result = push(source, "HEAD", f"refs/heads/{branch}")
        assert result.returncode == 0, f"Valid deployment corpus was rejected: {result.stderr}"
        git(REPO, "symbolic-ref", "HEAD", f"refs/heads/{branch}")

        # Cron was already asserted above; disable it to isolate this direct execution.
        run(["crontab", "-r"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["rm", "-rf", "/home/user/deploy_workspace"], check=True)

        for pid in listener_pids(9090):
            os.kill(pid, signal.SIGTERM)
        deadline = time.time() + 5
        while listener_pids(9090) and time.time() < deadline:
            time.sleep(0.1)
        assert not listener_pids(9090), "Could not replace the supplied API with the verification endpoint."

        capture = str(Path(capture_dir) / "requests.jsonl")
        server_py = str(Path(capture_dir) / "server.py")
        Path(server_py).write_text(r'''
import json, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
capture = sys.argv[1]
class Server(ThreadingHTTPServer):
    allow_reuse_address = True
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', '0'))
        body = self.rfile.read(length).decode('utf-8')
        row = {'path': self.path, 'content_type': self.headers.get('Content-Type'), 'body': body}
        with open(capture, 'a') as f:
            f.write(json.dumps(row) + '\n')
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'success\n')
    def log_message(self, *args):
        pass
Server(('127.0.0.1', 9090), Handler).serve_forever()
''')
        server = subprocess.Popen(["python3", server_py, capture])
        try:
            deadline = time.time() + 5
            while time.time() < deadline:
                with socket.socket() as sock:
                    if sock.connect_ex(("127.0.0.1", 9090)) == 0:
                        break
                time.sleep(0.1)
            else:
                pytest.fail("Verification API failed to start on port 9090.")

            result = run([DEPLOY], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
            assert result.returncode == 0, f"deploy.sh failed: {result.stderr}"
            time.sleep(0.5)
        finally:
            server.terminate()
            try:
                server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                server.kill()

        rows = [json.loads(line) for line in Path(capture).read_text().splitlines()] if Path(capture).exists() else []
        assert len(rows) == len(expected), f"Expected {len(expected)} dashboard POSTs, received {len(rows)}."
        assert all(row["path"] == "/api/dashboard" for row in rows), "deploy.sh posted to the wrong API path."
        assert all((row["content_type"] or "").split(";", 1)[0].strip().lower() == "application/json" for row in rows), \
            "deploy.sh did not send Content-Type: application/json."
        received = [json.loads(row["body"]) for row in rows]
        assert sorted(received, key=lambda x: x["id"]) == sorted(expected, key=lambda x: x["id"]), \
            "deploy.sh did not POST the contents of every repository JSON file."
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
