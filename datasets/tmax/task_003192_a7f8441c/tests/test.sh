#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import string
import json
import base64
import hmac
import hashlib
import re
import pytest

LIB_DIR = "/app/vendored/libsec-jwt"
AGENT_SOURCE = "/home/user/policy_enforcer.cpp"
AGENT_BINARY = "/home/user/build/policy_check"
NOW = 1700000000


def b64url(data):
    if isinstance(data, str):
        data = data.encode()
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def generate_jwt(alg, payload, secret, sig_type):
    header = {"alg": alg, "typ": "JWT"}
    hdr_b64 = b64url(json.dumps(header, separators=(",", ":")))
    pay_b64 = b64url(json.dumps(payload, separators=(",", ":")))
    msg = "%s.%s" % (hdr_b64, pay_b64)

    if sig_type == "valid":
        sig = hmac.new(secret.encode(), msg.encode(), hashlib.sha256).digest()
        sig_b64 = b64url(sig)
    elif sig_type == "garbage":
        sig_b64 = b64url(os.urandom(32))
    else:
        sig_b64 = ""
    return "%s.%s" % (msg, sig_b64)


def run_checked(command, **kwargs):
    try:
        return subprocess.run(command, check=True, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, **kwargs)
    except subprocess.CalledProcessError as exc:
        pytest.fail("Command failed: %r\nstdout:\n%s\nstderr:\n%s" % (
            command,
            exc.stdout.decode(errors="replace"),
            exc.stderr.decode(errors="replace")))


def test_library_build_and_validation():
    assert os.path.isfile(os.path.join(LIB_DIR, "Makefile")), "Vendored Makefile is missing"
    assert os.path.isfile(os.path.join(LIB_DIR, "include/libsec_jwt.h")), "Library header is missing"
    assert os.path.isfile(os.path.join(LIB_DIR, "src/validator.cpp")), "Library implementation is missing"

    run_checked(["make", "clean"], cwd=LIB_DIR, timeout=20)
    run_checked(["make"], cwd=LIB_DIR, timeout=30)
    library = os.path.join(LIB_DIR, "libsec-jwt.so")
    assert os.path.isfile(library), "Makefile did not build libsec-jwt.so"

    harness_source = r'''
#include <iostream>
#include <string>
#include "libsec_jwt.h"

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    std::string token;
    while (std::getline(std::cin, token)) {
        libsec_jwt::Header h;
        libsec_jwt::Payload p;
        if (libsec_jwt::validate_token(token, argv[1], h, p))
            std::cout << "VALID " << h.alg << " " << p.role << " " << p.exp << "\n";
        else
            std::cout << "INVALID\n";
    }
    return 0;
}
'''
    with open("/tmp/libsec_harness.cpp", "w") as f:
        f.write(harness_source)
    run_checked([
        "g++", "-std=c++11", "-I" + os.path.join(LIB_DIR, "include"),
        "/tmp/libsec_harness.cpp", "-L" + LIB_DIR, "-lsec-jwt",
        "-Wl,-rpath," + LIB_DIR, "-o", "/tmp/libsec_harness"
    ], timeout=30)

    secret = "library-test-secret-9K4v"
    good = generate_jwt("HS256", {"role": "admin", "exp": 1800000000}, secret, "valid")
    bad_sig = generate_jwt("HS256", {"role": "admin", "exp": 1800000000}, secret, "garbage")
    none_token = generate_jwt("none", {"role": "admin", "exp": 1800000000}, secret, "empty")
    wrong_alg_signed = generate_jwt("RS256", {"role": "admin", "exp": 1800000000}, secret, "valid")
    proc = run_checked(
        ["/tmp/libsec_harness", secret],
        input=("\n".join([good, bad_sig, none_token, wrong_alg_signed, "not.a.jwt"]) + "\n").encode(),
        timeout=10)
    output = proc.stdout.decode().splitlines()
    assert output == [
        "VALID HS256 admin 1800000000",
        "INVALID",
        "INVALID",
        "INVALID",
        "INVALID",
    ], "The vendored library does not strictly validate HS256 signatures and parse claims"


def test_policy_enforcer_behavior():
    assert os.path.isfile(AGENT_SOURCE), "policy_enforcer.cpp is missing"
    assert os.path.isfile(AGENT_BINARY), "Agent binary not found at %s" % AGENT_BINARY
    assert os.access(AGENT_BINARY, os.X_OK), "Agent binary is not executable"

    with open(AGENT_SOURCE, "r", errors="replace") as f:
        source = f.read()
    assert re.search(r"#\s*include\s*[<\"]libsec_jwt\.h[>\"]", source), \
        "policy_enforcer.cpp must include the vendored library header"
    assert "validate_token" in source, \
        "policy_enforcer.cpp must call libsec_jwt::validate_token"

    random.seed(42)
    secret_len = random.randint(16, 64)
    secret = "".join(random.choices(string.ascii_letters + string.digits, k=secret_len))
    inputs = []
    expected = []

    # Explicit positive and security-sensitive cases ensure an all-BLOCK program fails.
    explicit = [
        ("Bearer " + generate_jwt("HS256", {"role": "admin", "exp": 1800000000}, secret, "valid"), "PASS"),
        ("Bearer " + generate_jwt("HS256", {"role": "admin", "exp": NOW + 1}, secret, "valid"), "PASS"),
        ("Bearer " + generate_jwt("HS256", {"role": "admin", "exp": NOW}, secret, "valid"), "BLOCK"),
        ("Bearer " + generate_jwt("HS256", {"role": "user", "exp": 1800000000}, secret, "valid"), "BLOCK"),
        ("Bearer " + generate_jwt("HS256", {"role": "admin", "exp": 1800000000}, secret, "garbage"), "BLOCK"),
        ("Bearer " + generate_jwt("none", {"role": "admin", "exp": 1800000000}, secret, "empty"), "BLOCK"),
        ("Bearer " + generate_jwt("RS256", {"role": "admin", "exp": 1800000000}, secret, "valid"), "BLOCK"),
        ("Token " + generate_jwt("HS256", {"role": "admin", "exp": 1800000000}, secret, "valid"), "BLOCK"),
        ("Bearer not.a.jwt", "BLOCK"),
        ("Bearer ", "BLOCK"),
    ]
    for line, answer in explicit:
        inputs.append(line)
        expected.append(answer)

    algs = ["HS256", "none", "RS256", "invalid"]
    roles = ["admin", "user", "guest", ""]
    for _ in range(10000):
        alg = random.choice(algs)
        exp = random.choice([1600000000, 1800000000, None])
        role = random.choice(roles)
        sig_type = random.choice(["valid", "garbage", "empty"])

        payload = {}
        if exp is not None:
            payload["exp"] = exp
        if role:
            payload["role"] = role
        token = generate_jwt(alg, payload, secret, sig_type)

        first = random.random()
        if first < 0.05:
            line = "Bearer" + token
            proper_header = False
        elif random.random() < 0.05:
            line = "Token " + token
            proper_header = False
        else:
            line = "Bearer " + token
            proper_header = True

        inputs.append(line)
        should_pass = (
            proper_header and alg == "HS256" and sig_type == "valid" and
            role == "admin" and exp is not None and exp > NOW
        )
        expected.append("PASS" if should_pass else "BLOCK")

    proc = run_checked(
        [AGENT_BINARY, secret],
        input=("\n".join(inputs) + "\n").encode(),
        timeout=15)
    output = proc.stdout.decode(errors="replace").splitlines()

    assert len(output) == len(inputs), \
        "Expected %d lines of output, got %d" % (len(inputs), len(output))
    for i, (actual, wanted) in enumerate(zip(output, expected)):
        assert actual in ("PASS", "BLOCK"), \
            "Invalid output on line %d: %r" % (i + 1, actual)
        assert actual == wanted, \
            "Mismatch on input line %d:\nInput: %s\nExpected: %s\nActual: %s" % (
                i + 1, inputs[i], wanted, actual)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
