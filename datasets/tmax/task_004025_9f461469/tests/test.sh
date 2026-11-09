#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import string
import subprocess
import sys
import urllib.error
import urllib.request

import pytest

sys.path.insert(0, "/home/user/app")


def test_sanitizer_adversarial_corpus():
    try:
        from sanitizer import is_safe_query
    except ImportError:
        pytest.fail("Could not import is_safe_query from /home/user/app/sanitizer.py. Did you create the file and function correctly?")

    evil_dir = "/home/user/tests/corpora/evil/"
    clean_dir = "/home/user/tests/corpora/clean/"

    evil_failed = []
    if os.path.isdir(evil_dir):
        for filename in os.listdir(evil_dir):
            filepath = os.path.join(evil_dir, filename)
            if os.path.isfile(filepath):
                with open(filepath, 'r', encoding='utf-8') as f:
                    content = f.read()
                try:
                    if is_safe_query(content) is not False:
                        evil_failed.append(filename)
                except Exception as e:
                    evil_failed.append(f"{filename} (raised {type(e).__name__})")

    clean_failed = []
    if os.path.isdir(clean_dir):
        for filename in os.listdir(clean_dir):
            filepath = os.path.join(clean_dir, filename)
            if os.path.isfile(filepath):
                with open(filepath, 'r', encoding='utf-8') as f:
                    content = f.read()
                try:
                    if is_safe_query(content) is not True:
                        clean_failed.append(filename)
                except Exception as e:
                    clean_failed.append(f"{filename} (raised {type(e).__name__})")

    error_msg = []
    if evil_failed:
        error_msg.append(f"{len(evil_failed)} evil files bypassed the sanitizer: {', '.join(evil_failed)}")
    if clean_failed:
        error_msg.append(f"{len(clean_failed)} clean files were incorrectly blocked: {', '.join(clean_failed)}")

    if error_msg:
        pytest.fail(" | ".join(error_msg))


def _graphql(expr, field):
    return f"query {{ users @filter(expr: {json.dumps(expr)}) {{ {field} }} }}"


def test_sanitizer_generated_queries():
    from sanitizer import is_safe_query

    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))

    def ident(prefix):
        return prefix + "_" + "".join(rng.choice(string.ascii_lowercase) for _ in range(14))

    cases = []
    for _ in range(16):
        obj = ident("obj")
        field = ident("field")
        value = rng.randrange(1, 1000000)
        atom = f"{obj}.{field} == {value}"
        depth = rng.randrange(0, 5)
        safe_expr = "(" * depth + atom + ")" * depth
        cases.append((_graphql(safe_expr, ident("result")), True, "generated safe expression"))

        deep = rng.randrange(12, 80)
        evil_expr = "(" * deep + atom + ")" * deep
        cases.append((_graphql(evil_expr, ident("result")), False, "deeply nested expression"))

    # Parentheses and restricted-looking text inside string literals are values,
    # not expression nesting or schema-field access.
    cases.append((_graphql('user.note == "' + ('(' * 100) + 'ordinary text' + (')' * 100) + '"', ident("result")), True, "parentheses inside a string literal"))
    cases.append((_graphql('user.note == "__internal_migrated_schema"', ident("result")), True, "restricted text used only as a string value"))

    for _ in range(8):
        suffix = ident("branch")
        restricted = rng.choice([
            f"__internal_migrated_schema.{suffix} == 1",
            f"user.__internal_migrated_schema.{suffix} != 0",
            f"(__internal_migrated_schema.{suffix} == 1)",
        ])
        cases.append((_graphql(restricted, ident("result")), False, "restricted migrated-schema field access"))

    huge_depth = 2000 + rng.randrange(100)
    cases.append((_graphql("(" * huge_depth + "user.id == 1" + ")" * huge_depth, ident("result")), False, "memory-exhaustion nesting"))
    cases.append((_graphql("(" * huge_depth + "user.id == 1", ident("result")), False, "unbalanced memory-exhaustion input"))

    failures = []
    for query, expected, description in cases:
        try:
            actual = is_safe_query(query)
        except Exception as exc:
            failures.append(f"{description}: raised {type(exc).__name__}")
            continue
        if actual is not expected:
            failures.append(f"{description}: expected {expected}, got {actual!r}")

    assert not failures, "Generated sanitizer checks failed: " + " | ".join(failures)


def test_nginx_configuration():
    nginx_conf_path = "/home/user/app/nginx.conf"
    assert os.path.isfile(nginx_conf_path), f"{nginx_conf_path} does not exist"

    with open(nginx_conf_path, 'r', encoding='utf-8') as f:
        conf_content = f.read()

    # Preserve the original configuration assertions.
    assert "proxy_pass" in conf_content, "nginx.conf is missing a proxy_pass directive"
    assert "127.0.0.1:8000" in conf_content or "localhost:8000" in conf_content, "nginx.conf does not proxy to port 8000"

    checked = subprocess.run(
        ["nginx", "-t", "-c", nginx_conf_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=5,
    )
    assert checked.returncode == 0, "nginx.conf is not a valid Nginx configuration:\n" + checked.stdout

    uncommented = re.sub(r"#.*", "", conf_content)
    location = re.search(r"location\s+(?:\^~\s+|=\s+)?/graphql\b\s*\{([^{}]*)\}", uncommented, re.S)
    assert location, "nginx.conf has no /graphql location block"
    assert re.search(r"\bproxy_pass\s+http://(?:127\.0\.0\.1|localhost):8000(?:/)?\s*;", location.group(1)), \
        "The /graphql location does not proxy to the FastAPI backend on port 8000"


def _request(url, payload):
    request = urllib.request.Request(
        url,
        data=payload,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=3) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()
    except urllib.error.URLError as error:
        pytest.fail(f"Could not connect to {url}: {error}")


def test_nginx_proxy_live():
    token = secrets.token_hex(12)
    payload = json.dumps({"query": "query VerifyProxy { __typename }", "variables": {"token": token}}).encode()

    backend_status, backend_body = _request("http://127.0.0.1:8000/graphql", payload)
    proxy_status, proxy_body = _request("http://127.0.0.1:8080/graphql", payload)

    assert backend_status in (200, 400, 405), f"FastAPI /graphql returned unexpected HTTP status {backend_status}"
    assert proxy_status != 502, "Nginx returned 502 Bad Gateway. Is FastAPI running and Nginx configured correctly?"
    assert proxy_status in (200, 400, 405), f"Nginx /graphql returned unexpected HTTP status {proxy_status}"
    assert (proxy_status, proxy_body) == (backend_status, backend_body), \
        "The live Nginx /graphql response does not match the FastAPI backend response"


def test_redis_live():
    import redis
    try:
        client = redis.Redis(host="127.0.0.1", port=6379, socket_connect_timeout=2, socket_timeout=2)
        assert client.ping() is True, "Redis did not answer PING"
    except Exception as exc:
        pytest.fail(f"Redis is not running correctly on port 6379: {exc}")
TEST_EOF

if timeout 35s python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
