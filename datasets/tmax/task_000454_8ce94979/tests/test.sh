#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pathlib
import random
import shlex
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid

import pytest

NGINX_CONF = "/home/user/nginx.conf"
WRAPPER = "/home/user/run_filter.sh"
FILTER = "/home/user/cost_filter.py"


def fetch_health():
    req = urllib.request.Request("http://localhost:8080/health")
    with urllib.request.urlopen(req, timeout=5) as response:
        assert response.getcode() == 200, f"Expected 200 OK, got {response.getcode()}"
        payload = json.loads(response.read().decode("utf-8"))
        assert payload.get("status") == "ok"


def test_nginx_health():
    """Test that Nginx is correctly proxying to the new socket and returning 200 OK."""
    try:
        fetch_health()
    except urllib.error.HTTPError as e:
        pytest.fail(f"Expected 200 OK, got HTTPError {e.code}. Nginx proxying might still be broken.")
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx: {e.reason}. Is Nginx running?")


def parse_nginx(content):
    lexer = shlex.shlex(content, posix=True, punctuation_chars="{};")
    lexer.whitespace_split = True
    lexer.commenters = "#"
    root = {"header": (), "statements": [], "children": []}
    stack = [root]
    pending = []
    for token in lexer:
        if token == "{":
            assert pending, "Block without a directive"
            node = {"header": tuple(pending), "statements": [], "children": []}
            stack[-1]["children"].append(node)
            stack.append(node)
            pending = []
        elif token == ";":
            if pending:
                stack[-1]["statements"].append(tuple(pending))
                pending = []
        elif token == "}":
            assert not pending, "Unterminated directive before closing brace"
            assert len(stack) > 1, "Unexpected closing brace"
            stack.pop()
        else:
            pending.append(token)
    assert len(stack) == 1 and not pending, "Incomplete Nginx configuration"
    return root


def descendants(node):
    for child in node["children"]:
        yield child
        yield from descendants(child)


def test_nginx_config():
    """Verify the config semantically, reload it, and exercise the resulting proxy."""
    assert os.path.isfile(NGINX_CONF), f"Expected Nginx config {NGINX_CONF} to exist."
    with open(NGINX_CONF, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "/tmp/cost_dashboard.sock" in content, "Expected nginx.conf to point to the correct upstream socket '/tmp/cost_dashboard.sock'."
    assert "198.51.100.55" in content and "deny" in content, "Expected nginx.conf to contain a deny directive for 198.51.100.55."

    tree = parse_nginx(content)
    servers = [n for n in descendants(tree) if n["header"] and n["header"][0] == "server"]
    matching = []
    for server in servers:
        direct = server["statements"]
        listens_8080 = any(s[0] == "listen" and any("8080" in arg for arg in s[1:]) for s in direct)
        has_exact_deny = any(s == ("deny", "198.51.100.55") for s in direct)
        locations = [n for n in descendants(server) if n["header"] and n["header"][0] == "location"]
        has_socket_proxy = any(
            stmt[0] == "proxy_pass" and any("/tmp/cost_dashboard.sock" in arg for arg in stmt[1:])
            for location in locations for stmt in location["statements"]
        )
        if listens_8080 and has_exact_deny and has_socket_proxy:
            matching.append(server)
    assert matching, "The port 8080 server must directly deny 198.51.100.55 and proxy a location to /tmp/cost_dashboard.sock."

    checked = subprocess.run(["nginx", "-t", "-c", NGINX_CONF], capture_output=True, text=True, timeout=10)
    assert checked.returncode == 0, checked.stderr
    reloaded = subprocess.run(["nginx", "-s", "reload", "-c", NGINX_CONF], capture_output=True, text=True, timeout=10)
    assert reloaded.returncode == 0, reloaded.stderr

    last_error = None
    for _ in range(20):
        try:
            fetch_health()
            return
        except Exception as exc:
            last_error = exc
            time.sleep(0.1)
    raise AssertionError(f"Health endpoint failed after loading the submitted Nginx config: {last_error}")


def test_run_filter_script_contents():
    """Preserve content checks, then verify the wrapper's behavior with a probe controller."""
    assert os.path.isfile(WRAPPER), f"Expected wrapper script {WRAPPER} to exist."
    with open(WRAPPER, "r") as f:
        content = f.read()

    assert "TZ=" in content and "Etc/UTC" in content, "run_filter.sh must set TZ to 'Etc/UTC'"
    assert "LC_ALL=" in content and "en_US.UTF-8" in content, "run_filter.sh must set LC_ALL to 'en_US.UTF-8'"
    assert "cost_filter.py" in content, "run_filter.sh must execute cost_filter.py"
    syntax = subprocess.run(["bash", "-n", WRAPPER], capture_output=True, text=True)
    assert syntax.returncode == 0, syntax.stderr

    assert os.path.isfile(FILTER), f"Expected admission controller {FILTER} to exist."
    original = pathlib.Path(FILTER).read_bytes()
    original_mode = stat.S_IMODE(os.stat(FILTER).st_mode)
    probe_output = os.path.join(tempfile.gettempdir(), f"wrapper-probe-{uuid.uuid4().hex}.json")
    probe = b'''import json, os, sys\nwith open(os.environ["WRAPPER_PROBE_OUT"], "w") as f:\n    json.dump({"tz": os.environ.get("TZ"), "locale": os.environ.get("LC_ALL"), "args": sys.argv[1:]}, f)\n'''
    args = [f"/tmp/request {uuid.uuid4().hex}.json", f"extra-{uuid.uuid4().hex}"]
    try:
        pathlib.Path(FILTER).write_bytes(probe)
        os.chmod(FILTER, 0o755)
        env = os.environ.copy()
        env.update({"TZ": "Wrong/Zone", "LC_ALL": "C", "WRAPPER_PROBE_OUT": probe_output})
        result = subprocess.run(["bash", WRAPPER, *args], env=env, capture_output=True, timeout=10)
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        assert os.path.isfile(probe_output), "The wrapper did not execute /home/user/cost_filter.py"
        data = json.loads(pathlib.Path(probe_output).read_text())
        assert data["tz"] == "Etc/UTC", "The wrapper must set TZ=Etc/UTC for the controller process"
        assert data["locale"] == "en_US.UTF-8", "The wrapper must set LC_ALL=en_US.UTF-8 for the controller process"
        assert data["args"] == args, "The wrapper must pass all arguments unchanged to the controller"
    finally:
        pathlib.Path(FILTER).write_bytes(original)
        os.chmod(FILTER, original_mode)
        try:
            os.unlink(probe_output)
        except FileNotFoundError:
            pass


def run_case(command, document, expected):
    with tempfile.TemporaryDirectory(prefix=f"finops-{uuid.uuid4().hex}-") as directory:
        path = os.path.join(directory, f"deployment-{uuid.uuid4().hex}.json")
        with open(path, "w") as f:
            json.dump(document, f, indent=random.choice([None, 1, 3]))
        result = subprocess.run(command + [path], capture_output=True, timeout=10)
        assert result.returncode == expected, (
            f"Expected exit {expected} for {document!r}, got {result.returncode}. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )


def test_generated_admission_cases():
    """Exercise both the Python controller and wrapper on unpredictable paths and JSON values."""
    assert os.path.isfile(FILTER), f"Expected admission controller {FILTER} to exist."
    assert stat.S_ISREG(os.stat(FILTER).st_mode), f"Expected {FILTER} to be a regular file."
    compiled = subprocess.run([sys.executable, "-m", "py_compile", FILTER], capture_output=True, text=True)
    assert compiled.returncode == 0, compiled.stderr

    suffix = uuid.uuid4().hex
    over_limit = 501 + random.SystemRandom().randrange(1, 10000)
    cases = [
        ({"resources": []}, 0),
        ({"resources": [{"type": "compute", "size": f"m-{suffix}", "monthly_cost": 500}]}, 0),
        ({"note": 'compute x9 and "monthly_cost": 999 are only text', "resources": [{"type": "storage", "size": f"x-{suffix}", "monthly_cost": 7}]}, 0),
        ({"resources": [{"type": "compute", "size": f"x-{suffix}", "monthly_cost": 1}]}, 1),
        ({"resources": [{"type": "storage", "size": "safe", "monthly_cost": 2}, {"type": "compute", "size": f"p-{suffix}", "monthly_cost": 3}]}, 1),
        ({"resources": [{"type": "network", "size": f"ordinary-{suffix}", "monthly_cost": over_limit}]}, 1),
        ({"resources": [{"type": "compute", "size": f"c-{suffix}", "monthly_cost": 10}, {"type": "storage", "size": "archive", "monthly_cost": over_limit}]}, 1),
    ]
    for command in ([sys.executable, FILTER], ["bash", WRAPPER]):
        for document, expected in cases:
            run_case(command, document, expected)


def test_adversarial_corpus():
    """Preserve the original clean and evil corpus assertions."""
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.isfile(WRAPPER), f"Expected script {WRAPPER} to exist."
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if f.endswith('.json')]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if f.endswith('.json')]
    assert len(clean_files) > 0, "Clean corpus is empty."
    assert len(evil_files) > 0, "Evil corpus is empty."

    clean_modified = []
    evil_bypassed = []
    for f in clean_files:
        result = subprocess.run(["bash", WRAPPER, f], capture_output=True)
        if result.returncode != 0:
            clean_modified.append(os.path.basename(f))
    for f in evil_files:
        result = subprocess.run(["bash", WRAPPER, f], capture_output=True)
        if result.returncode == 0:
            evil_bypassed.append(os.path.basename(f))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if errors:
        pytest.fail(" | ".join(errors))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
