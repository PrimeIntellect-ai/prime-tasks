#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import re
import shutil
import signal
import stat
import subprocess
import tempfile
import time
import urllib.request
import uuid

import pytest
import redis
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

CLASSIFIER = "/home/user/classifier.py"
PIPELINE = "/app/audit_pipeline"


def process_cmdlines():
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/cmdline", "rb") as f:
                cmd = f.read().replace(b"\0", b" ").decode(errors="replace")
            with open(f"/proc/{name}/comm", "r") as f:
                comm = f.read().strip()
            found.append((int(name), comm, cmd))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return found


def worker_pids():
    return [pid for pid, _, cmd in process_cmdlines()
            if "/app/audit_pipeline/worker.py" in cmd]


def parse_classifier_output(result, expected_names):
    assert result.returncode == 0, result.stderr
    assert result.stderr == "", f"Classifier wrote to stderr: {result.stderr!r}"
    lines = result.stdout.splitlines()
    assert len(lines) == len(expected_names), (
        f"Expected exactly {len(expected_names)} output lines, got {len(lines)}: {lines!r}"
    )
    parsed = {}
    for line in lines:
        match = re.fullmatch(r"([^:\r\n]+): (CLEAN|EVIL)", line)
        assert match, f"Malformed classifier output line: {line!r}"
        name, label = match.groups()
        assert name not in parsed, f"Duplicate output for {name}"
        parsed[name] = label
    assert set(parsed) == set(expected_names), (
        f"Output filenames differ: expected {set(expected_names)!r}, got {set(parsed)!r}"
    )
    return parsed


def test_classifier_corpus():
    evil_dir = "/app/corpora/evil"
    clean_dir = "/app/corpora/clean"
    classifier_path = CLASSIFIER

    assert os.path.isfile(classifier_path), f"Classifier script missing at {classifier_path}"

    res_evil = subprocess.run(["python3", classifier_path, evil_dir], capture_output=True, text=True)
    evil_output = res_evil.stdout.strip().split('\n')
    evil_results = {}
    for line in evil_output:
        if ":" in line:
            fname, label = line.split(":", 1)
            evil_results[fname.strip()] = label.strip()

    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.log')]
    evil_bypassed = []
    for f in evil_files:
        if evil_results.get(f) != "EVIL":
            evil_bypassed.append(f)

    res_clean = subprocess.run(["python3", classifier_path, clean_dir], capture_output=True, text=True)
    clean_output = res_clean.stdout.strip().split('\n')
    clean_results = {}
    for line in clean_output:
        if ":" in line:
            fname, label = line.split(":", 1)
            clean_results[fname.strip()] = label.strip()

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.log')]
    clean_modified = []
    for f in clean_files:
        if clean_results.get(f) != "CLEAN":
            clean_modified.append(f)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    assert not errors, " | ".join(errors)


def test_classifier_generated_mixed_corpus():
    assert os.path.isfile(CLASSIFIER), f"Classifier script missing at {CLASSIFIER}"
    token = "SESSION_SEC_" + uuid.uuid4().hex[:16].upper()
    high_uid = random.randint(1001, 60000)
    cases = [
        ({"uid": 1000, "cmdline": ["tool", "--credential=" + token]}, "EVIL"),
        ({"uid": high_uid, "cmdline": ["sudo", "bash"], "tty": None}, "EVIL"),
        ({"uid": high_uid + 1, "cmdline": ["/bin/su", "root"]}, "EVIL"),
        ({"uid": 1000, "cmdline": ["sudo", "id"], "tty": None}, "CLEAN"),
        ({"uid": high_uid + 2, "cmdline": ["sudo", "id"], "tty": "/dev/pts/7"}, "CLEAN"),
        ({"uid": high_uid + 3, "cmdline": ["python3", "job.py"], "tty": None}, "CLEAN"),
        ({"uid": 1002, "cmdline": ["echo", "SESSION_SEC_1234-not-a-valid-token"]}, "CLEAN"),
    ]
    with tempfile.TemporaryDirectory(prefix="audit-classifier-") as directory:
        expected = {}
        random.shuffle(cases)
        for payload, label in cases:
            name = f"{uuid.uuid4().hex}.log"
            with open(os.path.join(directory, name), "w") as f:
                json.dump(payload, f)
            expected[name] = label
        # Non-log files must not produce output.
        with open(os.path.join(directory, f"{uuid.uuid4().hex}.txt"), "w") as f:
            f.write("not a log")
        result = subprocess.run(
            ["python3", CLASSIFIER, directory], capture_output=True, text=True, timeout=10
        )
        actual = parse_classifier_output(result, expected)
        assert actual == expected


def test_nginx_config_fixed():
    nginx_conf_path = "/app/audit_pipeline/config/nginx.conf"
    assert os.path.isfile(nginx_conf_path), "Nginx config file missing"
    with open(nginx_conf_path, "r") as f:
        content = f.read()

    assert "proxy_hide_header Cookie;" not in content or "proxy_pass_header Cookie;" in content, \
        "Nginx is still configured to drop the Cookie header."
    checked = subprocess.run(
        ["nginx", "-t", "-c", nginx_conf_path], capture_output=True, text=True
    )
    assert checked.returncode == 0, checked.stderr


def test_flask_api_fixed():
    api_path = "/app/audit_pipeline/api.py"
    assert os.path.isfile(api_path), "Flask API file missing"
    with open(api_path, "r") as f:
        content = f.read()

    assert "port=6380" not in content, "Flask API is still connecting to the broken Redis port (6380)."
    assert "6379" in content, "Flask API does not appear to connect to the correct Redis port (6379)."


def test_worker_fixed():
    worker_path = "/app/audit_pipeline/worker.py"
    assert os.path.isfile(worker_path), "Worker script missing"
    with open(worker_path, "r") as f:
        content = f.read()

    assert "--cred" not in content, "Worker is still passing credentials via the '--cred' command-line argument."
    assert "--read-stdin" in content, "Worker is not passing the '--read-stdin' flag to the logger."
    assert "input=" in content or "stdin=" in content or "communicate" in content, \
        "Worker does not appear to pipe the decrypted credential to stdin."


def test_services_running_and_cookie_reaches_redis():
    processes = process_cmdlines()
    assert any(comm == "nginx" for _, comm, _ in processes), "Nginx is not running"
    assert any(comm == "redis-server" for _, comm, _ in processes), "Redis is not running"
    assert any("/app/audit_pipeline/api.py" in cmd for _, _, cmd in processes), "Flask API is not running"
    pids = worker_pids()
    assert pids, "Audit worker is not running"

    client = redis.Redis(host="127.0.0.1", port=6379, socket_timeout=2)
    assert client.ping()
    cookie = "queuecheck_" + uuid.uuid4().hex

    stopped = []
    try:
        for pid in pids:
            os.kill(pid, signal.SIGSTOP)
            stopped.append(pid)
        time.sleep(0.15)
        client.delete("audit_jobs")
        request = urllib.request.Request(
            "http://127.0.0.1:8080/audit",
            headers={"Cookie": f"Audit-Session={cookie}"},
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            body = response.read().decode()
            assert response.status == 200
            assert body == "OK"
        queued = client.lrange("audit_jobs", 0, -1)
        assert queued == [cookie.encode()], f"Flask did not enqueue the raw cookie: {queued!r}"
        client.delete("audit_jobs")
    finally:
        for pid in stopped:
            try:
                os.kill(pid, signal.SIGCONT)
            except ProcessLookupError:
                pass


def test_encrypted_worker_job_uses_stdin_without_credential_argv():
    pids = worker_pids()
    assert pids, "Audit worker is not running"
    logger_path = "/app/audit_pipeline/bin/logger"
    key_path = "/app/audit_pipeline/keys/worker.key"
    assert os.path.isfile(logger_path)
    assert os.path.isfile(key_path)

    client = redis.Redis(host="127.0.0.1", port=6379, socket_timeout=2)
    assert client.ping()
    result_path = f"/tmp/logger-probe-{uuid.uuid4().hex}.json"
    credential = "probe-credential-" + uuid.uuid4().hex
    with open(key_path, "rb") as f:
        key = f.read()
    nonce = os.urandom(12)
    encrypted_job = nonce + AESGCM(key).encrypt(nonce, credential.encode(), None)

    with open(logger_path, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(logger_path).st_mode)
    probe = f'''#!/usr/bin/env python3
import base64, json, os, sys
payload = sys.stdin.buffer.read()
with open({result_path!r}, "w") as f:
    json.dump({{"argv": sys.argv[1:], "stdin": base64.b64encode(payload).decode()}}, f)
'''.encode()

    try:
        with open(logger_path, "wb") as f:
            f.write(probe)
        os.chmod(logger_path, 0o755)
        client.delete("audit_jobs")
        client.lpush("audit_jobs", encrypted_job)
        deadline = time.time() + 10
        while time.time() < deadline and not os.path.exists(result_path):
            time.sleep(0.1)
        assert os.path.exists(result_path), "Running worker did not process the encrypted Redis job"
        with open(result_path) as f:
            observed = json.load(f)
        assert observed["argv"] == ["--read-stdin"], (
            f"Logger received unexpected command-line arguments: {observed['argv']!r}"
        )
        assert credential not in "\0".join(observed["argv"]), "Credential leaked through argv"
        assert base64.b64decode(observed["stdin"]) == credential.encode(), (
            "Worker did not pass the decrypted credential through stdin"
        )
    finally:
        client.delete("audit_jobs")
        with open(logger_path, "wb") as f:
            f.write(original)
        os.chmod(logger_path, original_mode)
        try:
            os.unlink(result_path)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
