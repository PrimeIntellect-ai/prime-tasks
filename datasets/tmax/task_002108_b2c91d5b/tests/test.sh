#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import secrets
import stat
import string
import subprocess
import time
import urllib.error
import urllib.request

import pytest

NGINX_CONF = "/home/user/nginx/nginx.conf"
LOGROTATE_CONF = "/home/user/logrotate.conf"
WAF_PATH = "/home/user/waf.sh"


def fetch(url):
    req = urllib.request.Request(url, headers={"Cache-Control": "no-cache"})
    with urllib.request.urlopen(req, timeout=5) as response:
        return response.status, response.read()


def test_nginx_proxy_fixed():
    """Verify the active Nginx configuration proxies the backend on port 8081."""
    assert os.path.isfile(NGINX_CONF), f"Nginx configuration not found at {NGINX_CONF}"

    checked = subprocess.run(
        ["nginx", "-t", "-c", NGINX_CONF], capture_output=True, text=True
    )
    assert checked.returncode == 0, f"Nginx configuration is invalid: {checked.stderr}"

    dumped = subprocess.run(
        ["nginx", "-T", "-c", NGINX_CONF], capture_output=True, text=True
    )
    assert dumped.returncode == 0, f"Could not inspect Nginx configuration: {dumped.stderr}"
    effective = (dumped.stdout + dumped.stderr).lower()
    assert "proxy_pass" in effective, "The effective Nginx configuration has no proxy_pass"
    assert re.search(r"(?:127\.0\.0\.1|localhost):8081\b", effective), (
        "The effective Nginx configuration does not reference the backend on 127.0.0.1:8081"
    )

    pid_path = "/home/user/nginx/nginx.pid"
    assert os.path.isfile(pid_path), "Nginx PID file is missing; Nginx is not running"
    with open(pid_path) as f:
        pid = int(f.read().strip())
    assert os.path.exists(f"/proc/{pid}"), "The Nginx master process is not running"
    exe = os.path.realpath(f"/proc/{pid}/exe")
    assert os.path.basename(exe).startswith("nginx"), f"PID {pid} is not an Nginx process"

    reload_result = subprocess.run(
        ["nginx", "-s", "reload", "-c", NGINX_CONF], capture_output=True, text=True
    )
    assert reload_result.returncode == 0, f"Nginx could not reload the configuration: {reload_result.stderr}"

    # Preserve the original HTTP-200 assertion and additionally verify the known backend body.
    try:
        direct_status, direct_body = fetch("http://127.0.0.1:8081/")
        assert direct_status == 200
        assert direct_body.strip() == b"OK", f"Unexpected backend response: {direct_body!r}"

        status = None
        proxied_body = None
        for _ in range(20):
            try:
                status, proxied_body = fetch("http://127.0.0.1:8080/")
                if status == 200 and proxied_body == direct_body:
                    break
            except urllib.error.URLError:
                pass
            time.sleep(0.1)
        assert status == 200, f"Expected 200 OK, got {status}"
        assert proxied_body == direct_body, "Port 8080 did not return the backend's OK response"
    except urllib.error.HTTPError as e:
        pytest.fail(f"Nginx returned HTTP Error: {e.code} (Backend still not correctly proxied or Nginx not reloaded)")
    except urllib.error.URLError as e:
        pytest.fail(f"Could not connect to Nginx on port 8080: {e.reason}")

    # Use an unpredictable resource created only during verification. A fixed local 200 server
    # cannot know its path or body, while a functioning reverse proxy receives it from 8081.
    nonce = secrets.token_hex(20)
    filename = f"verifier-{nonce}.txt"
    backend_file = os.path.join("/home/user/backend", filename)
    expected = f"backend-proof-{secrets.token_urlsafe(32)}\n".encode()
    with open(backend_file, "wb") as f:
        f.write(expected)
    os.chmod(backend_file, 0o644)
    try:
        direct_status, direct_body = fetch(f"http://127.0.0.1:8081/{filename}?n={nonce}")
        assert direct_status == 200 and direct_body == expected, "The test backend did not serve the proof resource"
        proxy_status, proxy_body = fetch(f"http://127.0.0.1:8080/{filename}?n={nonce}")
        assert proxy_status == 200, f"Expected 200 OK for proxied proof resource, got {proxy_status}"
        assert proxy_body == direct_body, "Nginx did not proxy the unpredictable backend resource"
    finally:
        try:
            os.unlink(backend_file)
        except FileNotFoundError:
            pass


def test_logrotate_config():
    """Validate directives and exercise actual wildcard rotation and compression."""
    config_path = LOGROTATE_CONF
    assert os.path.exists(config_path), f"logrotate configuration file not found at {config_path}"

    with open(config_path, "r") as f:
        content = f.read().lower()

    # Keep the original assertions.
    assert "/home/user/nginx/logs/" in content and ".log" in content, "Target log path (/home/user/nginx/logs/*.log) not found in logrotate config"
    assert "daily" in content, "'daily' directive missing from logrotate config"
    assert "rotate 7" in content, "'rotate 7' directive missing from logrotate config"
    assert "compress" in content, "'compress' directive missing from logrotate config"
    assert "missingok" in content, "'missingok' directive missing from logrotate config"

    res = subprocess.run(["logrotate", "-d", config_path], capture_output=True, text=True)
    assert res.returncode == 0, f"logrotate configuration syntax is invalid: {res.stderr}"
    debug = (res.stdout + res.stderr).lower()
    assert re.search(r"\b7 rotations\b", debug), "Effective logrotate policy does not retain exactly 7 rotations"
    assert re.search(r"(?:after|every)\s+1\s+days?", debug) or "daily" in debug, (
        "Effective logrotate policy is not daily"
    )

    logs_dir = "/home/user/nginx/logs"
    directory_stat = os.stat(logs_dir)
    test_name = f"verifier_{secrets.token_hex(12)}.log"
    test_log = os.path.join(logs_dir, test_name)
    state_file = f"/tmp/logrotate-state-{secrets.token_hex(12)}"

    # The setup made this directory world-writable, which root logrotate intentionally rejects.
    # Temporarily give it normal user-owned permissions so both ordinary and `su user user`
    # user-space configurations can be exercised.
    os.chown(logs_dir, 1000, 1000)
    os.chmod(logs_dir, 0o755)
    try:
        with open(test_log, "w") as f:
            f.write("dynamic rotation payload " + secrets.token_hex(32) + "\n")
        os.chown(test_log, 1000, 1000)
        os.chmod(test_log, 0o644)

        rotated = subprocess.run(
            ["logrotate", "-f", "-s", state_file, config_path],
            capture_output=True,
            text=True,
        )
        assert rotated.returncode == 0, f"logrotate failed during an actual rotation: {rotated.stderr}"

        products = glob.glob(test_log + ".*")
        assert products, "The configured *.log rule did not rotate a dynamically named log file"
        compressed = [p for p in products if p.endswith(".gz")]
        assert compressed, f"The rotated test log was not compressed; products were: {products}"
        for path in compressed:
            check = subprocess.run(["gzip", "-t", path], capture_output=True, text=True)
            assert check.returncode == 0, f"Invalid compressed rotation {path}: {check.stderr}"
    finally:
        for path in glob.glob(test_log + "*"):
            try:
                os.unlink(path)
            except (FileNotFoundError, IsADirectoryError):
                pass
        try:
            os.unlink(state_file)
        except FileNotFoundError:
            pass
        os.chown(logs_dir, directory_stat.st_uid, directory_stat.st_gid)
        os.chmod(logs_dir, stat.S_IMODE(directory_stat.st_mode))


def run_waf(*args):
    return subprocess.run(["bash", WAF_PATH, *args], capture_output=True, timeout=5)


def test_waf_script_adversarial_corpus():
    """Keep corpus checks, then test unpredictable generated inputs and argument handling."""
    waf_path = WAF_PATH
    assert os.path.exists(waf_path), f"WAF script not found at {waf_path}"
    assert os.path.isfile(waf_path), f"WAF path is not a regular file: {waf_path}"

    evil_path = "/home/user/corpora/evil.txt"
    clean_path = "/home/user/corpora/clean.txt"
    assert os.path.exists(evil_path), "Evil corpus missing"
    assert os.path.exists(clean_path), "Clean corpus missing"

    with open(evil_path, "r") as f:
        evil_lines = [line.strip() for line in f if line.strip()]
    with open(clean_path, "r") as f:
        clean_lines = [line.strip() for line in f if line.strip()]

    evil_bypassed = []
    for line in evil_lines:
        res = run_waf(line)
        if res.returncode != 1:
            evil_bypassed.append(line)

    clean_modified = []
    for line in clean_lines:
        res = run_waf(line)
        if res.returncode != 0:
            clean_modified.append(line)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_lines)} evil bypassed. Offending examples: {evil_bypassed[:3]}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_lines)} clean modified (rejected). Offending examples: {clean_modified[:3]}")
    assert not evil_bypassed and not clean_modified, " | ".join(errors)

    nonce = secrets.token_urlsafe(24)
    punctuation = " ;'\"$()[]{}|&!?=+,%#@:\\ "
    generated_evil = []
    for pattern in ("<script>", "UNION SELECT", "../"):
        generated_evil.extend([
            pattern + nonce,
            nonce + pattern,
            f"prefix-{nonce}{punctuation}{pattern}{punctuation}suffix-{nonce}",
        ])
    generated_evil.append(f"{nonce}<script>{punctuation}UNION SELECT{punctuation}../{nonce}")

    generated_clean = [
        "",
        nonce,
        f"GET /safe/{nonce} HTTP/1.1",
        f"POST /submit HTTP/1.1 body={nonce}{punctuation}",
        f"{nonce}<script without closing angle bracket",
        f"{nonce} UNION value SELECT {nonce}",
        f"one-dot./safe/{nonce}",
        f"quotes ' \" and command text $(echo harmless) ; {nonce}",
    ]

    for line in generated_evil:
        result = run_waf(line)
        assert result.returncode == 1, f"Generated malicious input bypassed the WAF: {line!r} (exit {result.returncode})"
    for line in generated_clean:
        result = run_waf(line)
        assert result.returncode == 0, f"Generated clean input was rejected or errored: {line!r} (exit {result.returncode})"

    assert run_waf().returncode != 0, "WAF accepted zero arguments despite requiring exactly one"
    assert run_waf(nonce, nonce + "-second").returncode != 0, "WAF accepted two arguments despite requiring exactly one"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
