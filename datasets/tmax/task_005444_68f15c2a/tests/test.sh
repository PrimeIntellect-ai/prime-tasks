#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import tempfile
from pathlib import Path


def run_waf(waf_path, request_path):
    try:
        return subprocess.run(
            [waf_path, request_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        ).returncode
    except subprocess.TimeoutExpired:
        return None


def test_nginx_config_updated():
    path = "/home/user/nginx.conf"
    assert os.path.exists(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    # Check for proxy_pass http://127.0.0.1:8453;
    # Allow some whitespace variations
    match = re.search(r"proxy_pass\s+http://127\.0\.0\.1:8453\s*;", content)
    assert match is not None, "nginx.conf does not contain 'proxy_pass http://127.0.0.1:8453;'"


def test_waf_executable_exists():
    path = "/home/user/waf"
    source = "/home/user/waf.cpp"
    assert os.path.isfile(source), f"WAF C++ source {source} does not exist."
    assert os.path.isfile(path), f"WAF executable {path} does not exist."
    assert os.access(path, os.X_OK), f"WAF executable {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"WAF executable {path} is not a compiled ELF executable."


def test_waf_source_compiles():
    source = "/home/user/waf.cpp"
    assert os.path.isfile(source), f"WAF C++ source {source} does not exist."
    with tempfile.TemporaryDirectory(prefix="waf_build_") as tmpdir:
        output = os.path.join(tmpdir, "waf_from_source")
        result = subprocess.run(
            ["g++", "-std=c++17", "-O2", source, "-o", output],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, "waf.cpp does not compile as C++:\n" + result.stderr
        assert os.path.isfile(output) and os.access(output, os.X_OK)


def test_waf_corpus_checks():
    waf_path = "/home/user/waf"
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    assert os.path.exists(waf_path), f"WAF executable {waf_path} missing."
    assert os.path.exists(clean_dir), f"Clean corpus {clean_dir} missing."
    assert os.path.exists(evil_dir), f"Evil corpus {evil_dir} missing."

    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir) if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir) if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failed = []
    for fpath in clean_files:
        result = subprocess.run([waf_path, fpath], capture_output=True)
        if result.returncode != 0:
            clean_failed.append(os.path.basename(fpath))

    evil_failed = []
    for fpath in evil_files:
        result = subprocess.run([waf_path, fpath], capture_output=True)
        if result.returncode == 0:
            evil_failed.append(os.path.basename(fpath))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failed)}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")

    assert not errors, "WAF corpus checks failed: " + "; ".join(errors)


def test_waf_generated_requests_and_compiled_source():
    token = secrets.token_hex(12)
    cases = [
        (f"GET /index-{token}.html HTTP/1.1\nHost: localhost\n", True),
        (f"POST /login HTTP/1.1\nHost: localhost\n\nuser={token}", True),
        (f"GET /api/data?id={secrets.randbelow(1000000)} HTTP/1.1\n", True),
        (f"GET /search?q=ordinary-{token} HTTP/1.1\n", True),
        (f"GET /api/data?id=$(printf {token}) HTTP/1.1\n", False),
        (f"GET /api/data?id=$(echo {token}) HTTP/1.1\n", False),
        (f"POST /login HTTP/1.1\n\nuser=x' UNION SELECT {token} FROM users--", False),
        (f"POST /lookup HTTP/1.1\n\nvalue=x' UNION SELECT password FROM accounts--{token}", False),
        (f"GET /index.html?q=`printf {token}` HTTP/1.1\n", False),
        (f"GET /status?q=`echo {token}` HTTP/1.1\n", False),
    ]

    source = "/home/user/waf.cpp"
    submitted = "/home/user/waf"
    with tempfile.TemporaryDirectory(prefix="waf_cases_") as case_dir, tempfile.TemporaryDirectory(prefix="waf_rebuild_") as build_dir:
        rebuilt = os.path.join(build_dir, "waf")
        compile_result = subprocess.run(
            ["g++", "-std=c++17", "-O2", source, "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, "waf.cpp does not compile as C++:\n" + compile_result.stderr

        request_files = []
        for payload, safe in cases:
            request_path = Path(case_dir) / secrets.token_hex(16)
            request_path.write_text(payload)
            request_files.append((str(request_path), safe))

        for executable in (submitted, rebuilt):
            for request_path, safe in request_files:
                returncode = run_waf(executable, request_path)
                assert returncode is not None, f"{executable} timed out while analyzing a generated request"
                if safe:
                    assert returncode == 0, f"{executable} rejected a generated safe request"
                else:
                    assert returncode != 0, f"{executable} accepted a generated malicious request"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
