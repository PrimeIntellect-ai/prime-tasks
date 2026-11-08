#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import glob
import json
import os
import random
import re
import secrets
import string
import subprocess
import time
import urllib.error
import urllib.request
import zlib

import pytest
import redis

WAF_SCRIPT = "/home/user/waf.py"
CI_CD_SCRIPT = "/home/user/ci_cd.sh"
EVIL_DIR = "/app/corpora/evil/"
CLEAN_DIR = "/app/corpora/clean/"
BUILD_DIR = "/tmp/builds"


def run_waf(path):
    return subprocess.run(
        ["python3", WAF_SCRIPT, "--file", str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    ).returncode


def clear_build_artifacts():
    os.makedirs(BUILD_DIR, exist_ok=True)
    for pattern in ("**/*.so", "**/*.c"):
        for path in glob.glob(os.path.join(BUILD_DIR, pattern), recursive=True):
            if os.path.isfile(path) or os.path.islink(path):
                os.unlink(path)


def shared_objects():
    return [
        path for path in glob.glob(os.path.join(BUILD_DIR, "**/*.so"), recursive=True)
        if os.path.isfile(path)
    ]


def invoke_symbol(path, symbol, expected):
    code = (
        "import ctypes,sys; "
        "lib=ctypes.CDLL(sys.argv[1]); "
        "fn=getattr(lib,sys.argv[2]); fn.restype=ctypes.c_int; "
        "sys.exit(0 if fn()==int(sys.argv[3]) else 1)"
    )
    return subprocess.run(
        ["python3", "-c", code, path, symbol, str(expected)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    ).returncode == 0


def listening_ipv4(address, port):
    wanted_addr = "0100007F" if address == "127.0.0.1" else "00000000"
    wanted_port = f"{port:04X}"
    with open("/proc/net/tcp", "r") as f:
        next(f)
        for line in f:
            fields = line.split()
            local_addr, local_port = fields[1].split(":")
            state = fields[3]
            if local_addr.upper() == wanted_addr and local_port.upper() == wanted_port and state == "0A":
                return True
    return False


def process_named(name):
    for comm in glob.glob("/proc/[0-9]*/comm"):
        try:
            if open(comm).read().strip() == name:
                return True
        except (OSError, ProcessLookupError):
            pass
    return False


def post_build(source):
    data = json.dumps({"source_code": source}).encode("utf-8")
    req = urllib.request.Request(
        "http://127.0.0.1:8080/build",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as response:
        assert response.status == 200, f"Expected HTTP 200, got {response.status}"
        body = response.read().decode("utf-8")
    parsed = json.loads(body)
    assert "checksum" in parsed, "Response JSON missing 'checksum' key"
    return int(parsed["checksum"])


def test_waf_adversarial_corpus():
    assert os.path.isfile(WAF_SCRIPT), f"WAF script not found at {WAF_SCRIPT}"

    evil_files = glob.glob(os.path.join(EVIL_DIR, "*.json"))
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.json"))
    assert len(evil_files) > 0, "No evil files found in corpus."
    assert len(clean_files) > 0, "No clean files found in corpus."

    evil_bypassed = []
    clean_modified = []
    for evil_file in evil_files:
        if run_waf(evil_file) == 0:
            evil_bypassed.append(os.path.basename(evil_file))
    for clean_file in clean_files:
        if run_waf(clean_file) != 0:
            clean_modified.append(os.path.basename(clean_file))

    error_msg = []
    if evil_bypassed:
        error_msg.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msg.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_modified)}")
    assert not evil_bypassed and not clean_modified, "WAF accuracy failed:\n" + "\n".join(error_msg)


def test_waf_generated_unlabeled_payloads(tmp_path):
    assert os.path.isfile(WAF_SCRIPT)
    token = secrets.token_hex(8)
    cases = []

    for i in range(8):
        fn = "safe_" + token + "_" + str(i)
        a = secrets.randbelow(50000) + 1
        b = secrets.randbelow(50000) + 1
        cases.append((True, f"int {fn}(int x) {{ return x + {a} - {b}; }}"))

    calls = [
        'system("/bin/true")',
        'popen("/bin/true", "r")',
        'execve("/bin/true", 0, 0)',
        'fork()',
        'system /* randomized spacing */ ("/bin/true")',
        'popen\n("/bin/true", "r")',
        'execve ("/bin/true", 0, 0)',
        'fork /* call */ ()',
    ]
    for i, call in enumerate(calls):
        fn = "unsafe_" + token + "_" + str(i)
        cases.append((False, f"void {fn}(void) {{ {call}; }}"))

    random.SystemRandom().shuffle(cases)
    failures = []
    for expected_clean, source in cases:
        path = tmp_path / (secrets.token_hex(12) + ".json")
        path.write_text(json.dumps({"source_code": source}))
        accepted = run_waf(path) == 0
        if accepted != expected_clean:
            failures.append((expected_clean, source))
    assert not failures, f"WAF misclassified generated payloads: {failures}"


def test_nginx_config():
    config_path = "/etc/nginx/sites-enabled/build_api"
    assert os.path.isfile(config_path), f"Nginx config not found at {config_path}"
    with open(config_path, "r") as f:
        content = f.read()
        assert "8080" in content, "Nginx config does not seem to listen on port 8080"
        assert "5000" in content, "Nginx config does not seem to proxy to port 5000"

    check = subprocess.run(["nginx", "-t"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert check.returncode == 0, check.stdout + check.stderr
    dump = subprocess.run(["nginx", "-T"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert dump.returncode == 0, dump.stdout + dump.stderr
    effective = dump.stdout + dump.stderr
    assert re.search(r"\blisten\s+(?:[^;\n]*:)?8080(?:\s|;)", effective), "No effective Nginx listener on 8080"
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:5000\s*;", effective), "Nginx does not proxy to 127.0.0.1:5000"
    assert process_named("nginx"), "Nginx is not running"


def test_end_to_end_build_api():
    time.sleep(1)
    assert listening_ipv4("127.0.0.1", 5000), "Flask API is not listening specifically on 127.0.0.1:5000"

    cache = redis.Redis(host="127.0.0.1", port=6379, db=0)
    assert cache.ping(), "Redis is not available on port 6379"
    cache.delete("latest_build")
    clear_build_artifacts()

    marker = secrets.randbelow(1000000) + 1000
    symbol = "verify_build_" + secrets.token_hex(8)
    source = f"int {symbol}(void) {{ return {marker}; }}"

    try:
        returned_crc = post_build(source)
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to the build API via Nginx on port 8080: {e}")

    artifacts = shared_objects()
    assert artifacts, "The API did not write a .so under /tmp/builds"
    matching = []
    for artifact in artifacts:
        with open(artifact, "rb") as f:
            raw = f.read()
        assert raw.startswith(b"\x7fELF"), f"Build output is not an ELF shared object: {artifact}"
        if zlib.crc32(raw) == returned_crc and invoke_symbol(artifact, symbol, marker):
            matching.append(artifact)
    assert matching, "Returned checksum does not match a loadable compiled artifact with the submitted function"

    registered = cache.get("latest_build")
    assert registered is not None, "Build checksum was not registered in Redis"
    assert int(registered) == returned_crc, "Redis checksum does not match the API response"


def test_ci_cd_script_execution(tmp_path):
    assert os.path.isfile(CI_CD_SCRIPT), f"CI/CD script not found at {CI_CD_SCRIPT}"
    assert os.access(CI_CD_SCRIPT, os.X_OK), f"CI/CD script {CI_CD_SCRIPT} is not executable"

    test_dir = tmp_path / ("payloads_" + secrets.token_hex(6))
    test_dir.mkdir()
    names = sorted([secrets.token_hex(12) + ".json", secrets.token_hex(12) + ".json"])

    clean_marker = secrets.randbelow(1000000) + 2000000
    evil_marker = clean_marker + 1
    clean_symbol = "ci_clean_" + secrets.token_hex(8)
    evil_symbol = "ci_evil_" + secrets.token_hex(8)
    clean_source = f"int {clean_symbol}(void) {{ return {clean_marker}; }}"
    evil_source = f'#include <stdlib.h>\nint {evil_symbol}(void) {{ system(":"); return {evil_marker}; }}'

    (test_dir / names[0]).write_text(json.dumps({"source_code": clean_source}))
    (test_dir / names[1]).write_text(json.dumps({"source_code": evil_source}))

    log_file = "/home/user/build_pipeline.log"
    if os.path.exists(log_file):
        os.remove(log_file)
    clear_build_artifacts()
    cache = redis.Redis(host="127.0.0.1", port=6379, db=0)
    cache.delete("latest_build")

    result = subprocess.run(
        ["bash", CI_CD_SCRIPT, str(test_dir)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
    assert os.path.isfile(log_file), f"Log file {log_file} was not created by the CI/CD script."

    with open(log_file, "r") as f:
        log_content = f.read()
    assert "200" in log_content, "Expected HTTP 200 status in the log for the clean payload."
    assert "checksum" in log_content, "Expected 'checksum' in the log for the clean payload."

    registered = cache.get("latest_build")
    assert registered is not None, "CI/CD did not cause the clean build to be registered in Redis"
    registered_crc = int(registered)
    assert str(registered_crc) in log_content, "CI/CD log does not contain the returned build checksum"
    assert re.search(r"(?<!\d)200(?!\d)", log_content), "CI/CD log does not contain the HTTP 200 status code"

    artifacts = shared_objects()
    assert artifacts, "CI/CD did not produce a shared object for the clean payload"
    clean_matches = []
    for artifact in artifacts:
        with open(artifact, "rb") as f:
            raw = f.read()
        assert raw.startswith(b"\x7fELF"), f"CI/CD output is not an ELF shared object: {artifact}"
        if zlib.crc32(raw) == registered_crc and invoke_symbol(artifact, clean_symbol, clean_marker):
            clean_matches.append(artifact)
        assert not invoke_symbol(artifact, evil_symbol, evil_marker), "CI/CD submitted an evil payload that the WAF should reject"
    assert clean_matches, "CI/CD did not POST and compile the generated clean payload"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
