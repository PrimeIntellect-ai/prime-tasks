#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import tempfile
import shutil
import secrets
import html


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def test_server_fixed_go():
    file_path = "/home/user/server_fixed.go"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read()

    # Preserve the original source assertions.
    assert "html.EscapeString" in content, "The file does not use html.EscapeString to prevent XSS."
    assert "HttpOnly" in content and "true" in content, "The cookie does not have HttpOnly set to true."
    assert "Secure" in content and "true" in content, "The cookie does not have Secure set to true."
    assert "Content-Security-Policy" in content, "The Content-Security-Policy header is not set."
    assert "default-src 'self'" in content, "The Content-Security-Policy header value does not contain 'default-src 'self''."

    # Compile the submitted server and exercise its actual greet handler.
    payload = "<script>alert('" + secrets.token_hex(8) + "&cookie')</script>"
    with tempfile.TemporaryDirectory() as td:
        shutil.copy2(file_path, os.path.join(td, "server_fixed.go"))
        test_source = r'''package main

import (
    "html"
    "net/http/httptest"
    "net/url"
    "strings"
    "testing"
)

func TestGreetSecurity(t *testing.T) {
    payload := PAYLOAD
    req := httptest.NewRequest("GET", "/greet?name="+url.QueryEscape(payload), nil)
    rec := httptest.NewRecorder()
    greetHandler(rec, req)
    res := rec.Result()

    if res.StatusCode != 200 {
        t.Fatalf("unexpected status: %d", res.StatusCode)
    }
    if got := res.Header.Get("Content-Security-Policy"); got != "default-src 'self'" {
        t.Fatalf("wrong CSP header: %q", got)
    }

    found := false
    for _, cookie := range res.Cookies() {
        if cookie.Name == "session_token" {
            found = true
            if !cookie.HttpOnly || !cookie.Secure {
                t.Fatalf("session_token flags: HttpOnly=%v Secure=%v", cookie.HttpOnly, cookie.Secure)
            }
        }
    }
    if !found {
        t.Fatal("session_token cookie was not set")
    }

    body := rec.Body.String()
    escaped := html.EscapeString(payload)
    if !strings.Contains(body, escaped) {
        t.Fatalf("response does not contain escaped name; body=%q expected fragment=%q", body, escaped)
    }
    if strings.Contains(body, payload) {
        t.Fatalf("response contains the unescaped payload: %q", body)
    }
}
'''.replace("PAYLOAD", repr(payload).replace("'", '"').replace('"<', '"<', 1))
        # Use a safely quoted Go string literal generated through JSON syntax.
        import json
        test_source = test_source.replace(repr(payload).replace("'", '"').replace('"<', '"<', 1), json.dumps(payload))
        with open(os.path.join(td, "server_fixed_test.go"), "w") as f:
            f.write(test_source)

        env = os.environ.copy()
        env["GO111MODULE"] = "off"
        result = subprocess.run(
            ["go", "test", "-run", "TestGreetSecurity", "-v"],
            cwd=td,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=30,
        )
        assert result.returncode == 0, "server_fixed.go failed compilation or behavioral tests:\n" + result.stdout


def test_analyze_sh():
    file_path = "/home/user/analyze.sh"
    assert os.path.isfile(file_path), f"File {file_path} is missing."
    st = os.stat(file_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {file_path} is not executable."


def test_compromised_ips():
    file_path = "/home/user/compromised_ips.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing. Did you run your script?"
    expected_ips = ["10.0.0.5", "192.168.1.11"]
    lines = read_nonempty_lines(file_path)
    assert lines == expected_ips, f"Expected IPs {expected_ips}, but got {lines}."


def test_analyze_script_behavior():
    script = "/home/user/analyze.sh"
    access = "/home/user/access.log"
    output = "/home/user/compromised_ips.txt"
    original_access = open(access, "rb").read()

    n = secrets.randbelow(150) + 20
    attack_a = f"10.77.3.{n}"
    attack_b = f"203.0.113.{secrets.randbelow(150) + 20}"
    blocked = f"198.51.100.{secrets.randbelow(150) + 20}"
    false_positive = f"172.20.4.{secrets.randbelow(150) + 20}"
    expected = sorted({attack_a, attack_b})

    fixture = "\n".join([
        f'{attack_b} - - [12/Sep/2026:10:00:00 +0000] "GET /greet?name=%3Cscript%3Eone%3C/script%3E HTTP/1.1" 200 111',
        f'{blocked} - - [12/Sep/2026:10:00:01 +0000] "GET /greet?name=%3Cscript%3Eblocked%3C/script%3E HTTP/1.1" 403 200',
        f'{attack_a} - - [12/Sep/2026:10:00:02 +0000] "POST /other/%3cScRiPt%3e HTTP/1.1" 200 99',
        f'{attack_b} - - [12/Sep/2026:10:00:03 +0000] "GET /again?x=%3CSCRIPT%3E HTTP/1.1" 200 88',
        f'{false_positive} - - [12/Sep/2026:10:00:04 +0000] "GET /greet?name=safe HTTP/1.1" 200 77 "-" "%3Cscript%3E-in-user-agent"',
        f'192.0.2.9 - - [12/Sep/2026:10:00:05 +0000] "GET /ordinary HTTP/1.1" 404 200',
    ]) + "\n"

    env = os.environ.copy()
    env["LC_ALL"] = "C"
    dynamic_result = None
    dynamic_lines = None
    try:
        with open(access, "w") as f:
            f.write(fixture)
        if os.path.exists(output):
            os.remove(output)
        dynamic_result = subprocess.run(
            [script], cwd="/home/user", env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
        )
        if os.path.isfile(output):
            dynamic_lines = read_nonempty_lines(output)
    finally:
        with open(access, "wb") as f:
            f.write(original_access)
        if os.path.exists(output):
            os.remove(output)
        restored_result = subprocess.run(
            [script], cwd="/home/user", env=env, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20
        )

    assert dynamic_result is not None and dynamic_result.returncode == 0, \
        "analyze.sh failed on a generated access log:\n" + (dynamic_result.stdout if dynamic_result else "not run")
    assert dynamic_lines is not None, "analyze.sh did not create /home/user/compromised_ips.txt"
    assert dynamic_lines == expected, f"Generated-log result should be {expected}, got {dynamic_lines}"

    assert restored_result.returncode == 0, "analyze.sh failed on the provided access log:\n" + restored_result.stdout
    original_expected = ["10.0.0.5", "192.168.1.11"]
    assert os.path.isfile(output), "analyze.sh did not regenerate compromised_ips.txt for the provided log"
    assert read_nonempty_lines(output) == original_expected
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
