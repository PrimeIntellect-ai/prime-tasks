#!/bin/bash
set +e
mkdir -p /logs/verifier

ORIGINAL_PARSER="/tmp/crd_parser.verifier.$$"
WRAPPER_LOG="/tmp/crd_parser.calls.$$"
export CRD_PARSER_ORIGINAL="$ORIGINAL_PARSER"
export CRD_PARSER_WRAPPER_LOG="$WRAPPER_LOG"

cleanup() {
    if [ -e "$ORIGINAL_PARSER" ]; then
        rm -f /app/crd_parser
        mv "$ORIGINAL_PARSER" /app/crd_parser
        chmod +x /app/crd_parser
    fi
}
trap cleanup EXIT

if ! mv /app/crd_parser "$ORIGINAL_PARSER"; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'WRAPPER_EOF' > /app/crd_parser
#!/usr/bin/env python3
import hashlib
import json
import os
import subprocess
import sys

original = os.environ["CRD_PARSER_ORIGINAL"]
log_path = os.environ["CRD_PARSER_WRAPPER_LOG"]

proc = subprocess.run([original] + sys.argv[1:], capture_output=True, text=True)
if proc.returncode != 0:
    sys.stderr.write(proc.stderr)
    sys.exit(proc.returncode)

try:
    file_index = sys.argv.index("-f") + 1
    file_path = sys.argv[file_index]
    payload = open(file_path, "rb").read()
    result = json.loads(proc.stdout)
except Exception as exc:
    sys.stderr.write(str(exc) + "\n")
    sys.exit(1)

result["input_sha256"] = hashlib.sha256(payload).hexdigest()
result["verification_nonce"] = os.environ["VERIFIER_NONCE"]
record = {
    "argv": sys.argv[1:],
    "file": os.path.realpath(file_path),
    "input_sha256": result["input_sha256"],
    "output": result,
}
with open(log_path, "a") as log:
    log.write(json.dumps(record, sort_keys=True) + "\n")
print(json.dumps(result, sort_keys=True))
WRAPPER_EOF
chmod 755 /app/crd_parser
: > "$WRAPPER_LOG"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import stat
import subprocess
import time
import uuid

import pytest
import requests

REPO = "/home/user/operator.git"
STAGING = "/home/user/staging"
WEBROOT = "/home/user/webroot"
DEPLOYMENT_JSON = WEBROOT + "/deployment.json"
LATEST_JSON = WEBROOT + "/latest.json"
TEST_REPO = "/tmp/test-repo"
WRAPPER_LOG = os.environ["CRD_PARSER_WRAPPER_LOG"]


def listener_pids():
    socket_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local_address, state = fields[1], fields[3]
            if state != "0A":
                continue
            host, port = local_address.rsplit(":", 1)
            if port.upper() != "1F90":
                continue
            if host.upper() not in ("0100007F", "00000000000000000000000001000000"):
                continue
            socket_inodes.add(fields[9])

    pids = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in socket_inodes:
                    pids.add(int(entry))
        except OSError:
            pass
    return pids


def assert_server_artifacts_and_process():
    source = "/home/user/server.c"
    binary = "/home/user/server"
    assert os.path.isfile(source), f"C source missing at {source}"
    assert os.path.isfile(binary), f"HTTP server binary missing at {binary}"
    assert os.access(binary, os.X_OK), f"HTTP server at {binary} is not executable"
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{binary} is not a compiled ELF executable"
    syntax = subprocess.run(["gcc", "-fsyntax-only", source], capture_output=True, text=True)
    assert syntax.returncode == 0, f"{source} is not valid C source: {syntax.stderr}"

    expected = os.path.realpath(binary)
    pids = listener_pids()
    assert pids, "No process is listening on 127.0.0.1:8080"
    executables = []
    for pid in pids:
        try:
            executables.append(os.path.realpath(f"/proc/{pid}/exe"))
        except OSError:
            pass
    assert expected in executables, (
        f"Port 127.0.0.1:8080 is not served by {binary}; listener executables: {executables}"
    )


def test_git_repo_setup():
    assert os.path.isdir(os.path.join(REPO, "objects")), f"{REPO} is not a bare git repository"
    bare = subprocess.check_output(["git", "-C", REPO, "rev-parse", "--is-bare-repository"], text=True).strip()
    assert bare == "true", f"{REPO} is not configured as a bare Git repository"
    assert os.path.isdir(STAGING), f"Staging directory missing at {STAGING}"
    assert os.path.isdir(WEBROOT), f"Web root directory missing at {WEBROOT}"

    hook_path = os.path.join(REPO, "hooks/post-receive")
    assert os.path.isfile(hook_path), f"post-receive hook missing at {hook_path}"
    assert os.access(hook_path, os.X_OK), f"post-receive hook at {hook_path} is not executable"
    with open(hook_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"post-receive hook at {hook_path} is not a compiled ELF executable"


def test_server_setup():
    assert_server_artifacts_and_process()


def read_calls():
    calls = []
    with open(WRAPPER_LOG) as f:
        for line in f:
            if line.strip():
                calls.append(json.loads(line))
    return calls


def push_and_check(payload, commit_message):
    crd_path = os.path.join(TEST_REPO, "deployment.crd")
    with open(crd_path, "w") as f:
        f.write(payload)
    subprocess.run(["git", "-C", TEST_REPO, "add", "deployment.crd"], check=True)
    subprocess.run(["git", "-C", TEST_REPO, "commit", "-m", commit_message], check=True)

    trace_path = f"/tmp/push-trace-{uuid.uuid4().hex}"
    push_proc = subprocess.run(
        ["strace", "-f", "-e", "trace=execve", "-o", trace_path,
         "git", "-C", TEST_REPO, "push", "origin", "master"],
        capture_output=True, text=True,
    )
    assert push_proc.returncode == 0, f"Git push failed: {push_proc.stderr}"
    trace = open(trace_path, errors="replace").read()
    assert re.search(r'execve\("/app/crd_parser"', trace), (
        "The post-receive hook did not execute /app/crd_parser"
    )

    staged_crd = os.path.join(STAGING, "deployment.crd")
    assert os.path.isfile(staged_crd), f"Expected pushed deployment.crd in {STAGING}"
    assert open(staged_crd).read() == payload, "Staging does not contain the incoming CRD revision"

    assert os.path.isfile(DEPLOYMENT_JSON), f"Expected {DEPLOYMENT_JSON} to be created by the hook"
    mode = stat.S_IMODE(os.stat(DEPLOYMENT_JSON).st_mode)
    assert mode == 0o600, f"Expected permissions 0600 for {DEPLOYMENT_JSON}, got {oct(mode)}"
    assert os.path.islink(LATEST_JSON), f"{LATEST_JSON} must be a symlink"
    target = os.readlink(LATEST_JSON)
    if not os.path.isabs(target):
        target = os.path.abspath(os.path.join(os.path.dirname(LATEST_JSON), target))
    assert target == DEPLOYMENT_JSON, f"Symlink {LATEST_JSON} does not point to {DEPLOYMENT_JSON}"

    digest = hashlib.sha256(payload.encode()).hexdigest()
    matching = [c for c in read_calls()
                if c.get("file") == staged_crd and c.get("input_sha256") == digest]
    assert matching, "Parser was not invoked on the pushed staging/deployment.crd contents"
    call = matching[-1]
    assert "-f" in call["argv"] and "-k" in call["argv"], "Parser was not called with its required file and key arguments"
    expected = call["output"]

    try:
        file_data = json.load(open(DEPLOYMENT_JSON))
    except (ValueError, OSError) as exc:
        pytest.fail(f"{DEPLOYMENT_JSON} is not the parser's valid JSON output: {exc}")
    assert file_data == expected, "deployment.json is not the output produced by /app/crd_parser"
    assert file_data.get("status") == "parsed"
    assert file_data.get("input_sha256") == digest
    assert file_data.get("verification_nonce") == os.environ["VERIFIER_NONCE"]

    try:
        resp = requests.get("http://127.0.0.1:8080/api/v1/manifest", timeout=2)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to HTTP server: {exc}")
    assert resp.status_code == 200, f"Expected HTTP 200 OK, got {resp.status_code}"
    assert "application/json" in resp.headers.get("Content-Type", ""), (
        f"Expected Content-Type: application/json, got {resp.headers.get('Content-Type', '')}"
    )
    try:
        served = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text}")
    assert served == expected, "HTTP endpoint did not return the current latest.json contents"
    assert served.get("status") == "parsed"
    return expected


def test_git_push_and_http_server():
    subprocess.run(["rm", "-rf", TEST_REPO], check=False)
    clone_proc = subprocess.run(["git", "clone", REPO, TEST_REPO], capture_output=True, text=True)
    assert clone_proc.returncode == 0, f"Failed to clone repository: {clone_proc.stderr}"
    subprocess.run(["git", "-C", TEST_REPO, "config", "user.email", "verifier@example.invalid"], check=True)
    subprocess.run(["git", "-C", TEST_REPO, "config", "user.name", "Verifier"], check=True)
    subprocess.run(["git", "-C", TEST_REPO, "checkout", "-B", "master"], check=True)

    first = f"kind: CustomDeployment\nvalue: {uuid.uuid4().hex}\n"
    second = f"kind: CustomDeployment\nvalue: {uuid.uuid4().hex}\n"
    first_result = push_and_check(first, "First verifier CRD")
    second_result = push_and_check(second, "Second verifier CRD")
    assert first_result != second_result, "A later push did not produce fresh parser output"

    other = requests.get("http://127.0.0.1:8080/not-the-manifest", timeout=2)
    assert other.status_code != 200, "The server must expose the manifest only at /api/v1/manifest"
    assert_server_artifacts_and_process()


def test_crontab_setup():
    script_path = "/home/user/health.sh"
    assert os.path.isfile(script_path), f"Health check script missing at {script_path}"
    script = open(script_path).read()
    assert "curl" in script, "Health check script does not use curl"
    assert "http://127.0.0.1:8080/api/v1/manifest" in script, "Health check uses the wrong endpoint"
    assert "/home/user/health.log" in script, "Health check does not write /home/user/health.log"

    try:
        output = subprocess.check_output(["crontab", "-l"], text=True)
    except subprocess.CalledProcessError:
        pytest.fail("crontab command failed or no crontab configured for user")
    assert script_path in output, f"{script_path} not found in user crontab"
    active = [line.strip() for line in output.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    assert any(re.match(r"^\*\s+\*\s+\*\s+\*\s+\*\s+.*?/home/user/health\.sh(?:\s|$)", line) for line in active), (
        "Health check is not scheduled every minute"
    )

    marker = f"verifier-{uuid.uuid4().hex}\n"
    with open("/home/user/health.log", "w") as f:
        f.write(marker)
    run = subprocess.run(["/bin/sh", script_path], capture_output=True, text=True, timeout=10)
    assert run.returncode == 0, f"Health check script failed: {run.stderr}"
    contents = open("/home/user/health.log").read()
    assert contents.startswith(marker), "Health check overwrote health.log instead of appending"
    appended = contents[len(marker):].strip().splitlines()
    assert appended and appended[-1].strip() == "200", (
        f"Health check did not append the manifest endpoint's HTTP 200 status: {contents!r}"
    )
TEST_EOF

export VERIFIER_NONCE="$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
cleanup
trap - EXIT

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
