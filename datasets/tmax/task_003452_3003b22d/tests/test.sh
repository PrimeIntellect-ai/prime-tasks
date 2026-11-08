#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import random
import secrets
import subprocess
from urllib.parse import parse_qs, urlencode, urlparse

AGENT_PATH = "/home/user/policy.py"
SALT = "winter storm"
VALID_OUTPUTS = {
    "ALLOW",
    "DENY: INVALID_SIGNATURE",
    "DENY: MALICIOUS_PAYLOAD",
    "DENY: OPEN_REDIRECT",
}


def signature(host, path):
    return hashlib.sha256(f"{host}{path}{SALT}".encode()).hexdigest()


def expected_result(data):
    host = data["host"]
    path = data["path"]
    cookie = data["cookie"]

    if cookie != f"auth_sig={signature(host, path)}":
        return "DENY: INVALID_SIGNATURE"

    query = parse_qs(urlparse(path).query)
    next_value = query.get("next", [""])[0]

    if next_value:
        lowered = next_value.lower()
        if any(pattern in lowered for pattern in ("javascript:", "data:", "../")):
            return "DENY: MALICIOUS_PAYLOAD"

        if next_value.startswith("//"):
            return "DENY: OPEN_REDIRECT"

        parsed_next = urlparse(next_value)
        if parsed_next.scheme in ("http", "https") and parsed_next.hostname != host:
            return "DENY: OPEN_REDIRECT"

    return "ALLOW"


def run_agent(data):
    proc = subprocess.run(
        ["python3", AGENT_PATH],
        input=json.dumps(data).encode(),
        capture_output=True,
        timeout=5,
    )
    assert proc.returncode == 0, proc.stderr.decode(errors="replace")

    stdout = proc.stdout.decode(errors="replace")
    lines = stdout.splitlines()
    assert len(lines) == 1, f"Expected exactly one output line, got {stdout!r}"
    assert lines[0] in VALID_OUTPUTS, f"Unexpected output: {lines[0]!r}"
    return lines[0]


def make_case(host, path, cookie=None):
    if cookie is None:
        cookie = f"auth_sig={signature(host, path)}"
    return {"host": host, "path": path, "cookie": cookie}


def test_policy_exists_and_is_executable_by_python():
    assert os.path.isfile(AGENT_PATH), f"Agent script missing: {AGENT_PATH}"
    case = make_case("example.com", "/login")
    assert run_agent(case) == "ALLOW"


def test_curated_policy_cases():
    cases = []

    # Valid requests, including no next parameter and same-host absolute URLs.
    cases.extend([
        make_case("example.com", "/login"),
        make_case("example.com", "/login?next=%2Fdashboard"),
        make_case("example.com", "/login?next=https%3A%2F%2Fexample.com%2Fhome"),
        make_case("test.org", "/login?x=1&next=%2Faccount%3Ftab%3Dsecurity"),
        make_case("app.local", "/login?next=https%3A%2F%2Fapp.local%3A8443%2Fhome"),
    ])

    # Malicious values, including mixed case and URL-encoded input.
    for value in (
        "javascript:alert(1)",
        "JaVaScRiPt:alert(1)",
        "data:text/html,<h1>x</h1>",
        "DATA:text/plain,test",
        "../etc/passwd",
        "/safe/../../secret",
    ):
        path = "/login?" + urlencode({"next": value})
        cases.append(make_case("example.com", path))

    # Open redirects and allowed same-host absolute redirects.
    for value in (
        "//attacker.example/steal",
        "https://evil.example/login",
        "http://evil.example/login",
        "https://example.com.evil.example/login",
        "https://user@example.net/login",
    ):
        path = "/login?" + urlencode({"next": value})
        cases.append(make_case("example.com", path))

    # Signature validation has first precedence, even for otherwise bad paths.
    bad_paths = [
        "/login?next=javascript%3Aalert%281%29",
        "/login?next=https%3A%2F%2Fevil.example%2F",
        "/login?next=%2F%2Fattacker.example%2F",
    ]
    for path in bad_paths:
        cases.append(make_case("example.com", path, "auth_sig=" + "0" * 64))

    # The complete signature must match; prefixes, suffixes, and case changes fail.
    host = "example.com"
    path = "/login?next=%2Fdashboard"
    digest = signature(host, path)
    invalid_cookies = [
        "auth_sig=" + digest[:-1],
        "auth_sig=" + digest + "0",
        "auth_sig=" + ("0" if digest[0] != "0" else "1") + digest[1:],
        "auth_sig=" + digest.upper(),
        "auth_sig=" + "f" * 64,
    ]
    for cookie in invalid_cookies:
        cases.append(make_case(host, path, cookie))

    for case in cases:
        assert run_agent(case) == expected_result(case), f"Input: {case!r}"


def test_randomized_policy_cases():
    rng = random.SystemRandom()
    hosts = ["example.com", "test.org", "app.local", "service.internal"]
    malicious_values = [
        "javascript:alert(1)",
        "JaVaScRiPt:confirm(1)",
        "data:text/html,test",
        "DaTa:application/json,{}",
        "../etc/passwd",
        "/one/../../two",
    ]

    for i in range(1000):
        host = rng.choice(hosts)
        nonce = secrets.token_hex(8)
        category = i % 5

        if category == 0:
            path = f"/login/{nonce}?" + urlencode({"next": "/dashboard"})
            digest = signature(host, path)
            pos = rng.randrange(len(digest))
            replacement = "0" if digest[pos] != "0" else "1"
            cookie = f"auth_sig={digest[:pos]}{replacement}{digest[pos + 1:]}"
            case = make_case(host, path, cookie)
        elif category == 1:
            path = f"/login/{nonce}?" + urlencode({"next": rng.choice(malicious_values)})
            case = make_case(host, path)
        elif category == 2:
            target = rng.choice([
                f"https://evil-{nonce}.example/path",
                f"http://attacker-{nonce}.example/path",
                f"//outside-{nonce}.example/path",
            ])
            path = f"/login/{nonce}?" + urlencode({"next": target})
            case = make_case(host, path)
        elif category == 3:
            target = rng.choice([
                f"/dashboard/{nonce}",
                f"https://{host}/home/{nonce}",
                f"http://{host}/account/{nonce}",
            ])
            path = f"/login/{nonce}?" + urlencode({"next": target})
            case = make_case(host, path)
        else:
            path = f"/login/{nonce}?source=test"
            case = make_case(host, path)

        assert run_agent(case) == expected_result(case), f"Input: {case!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
