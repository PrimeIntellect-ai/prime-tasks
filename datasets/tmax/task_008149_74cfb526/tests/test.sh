#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import secrets
import string
import subprocess


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def token(header, payload, signature=""):
    return f"{b64url(header)}.{b64url(payload)}.{signature}"


def test_ssh_keys_remediated():
    auth_keys_path = "/home/user/.ssh/authorized_keys"
    assert os.path.isfile(auth_keys_path), f"{auth_keys_path} is missing."

    with open(auth_keys_path, "r") as f:
        content = f.read()

    assert "legitimate@corp.com" in content, "Legitimate admin key was removed."
    assert "hacker@pwned" not in content, "Attacker's SSH key is still present."

    expected = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3... legitimate@corp.com\n"
    assert content == expected, "authorized_keys was not remediated by removing only the attacker's key."


def test_exploit_go_output():
    exploit_path = "/home/user/exploit.go"
    assert os.path.isfile(exploit_path), f"{exploit_path} is missing."

    result = subprocess.run(
        ["go", "run", exploit_path],
        capture_output=True,
        text=True,
        timeout=30,
    )

    assert result.returncode == 0, f"exploit.go failed to run:\n{result.stderr}"

    output = result.stdout.strip()
    expected_jwt = "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJyb2xlIjoiYWRtaW4ifQ."
    assert output == expected_jwt, f"exploit.go printed '{output}', expected '{expected_jwt}'"


def test_server_go_patched_and_existing_behavior_preserved():
    server_path = "/home/user/app/server.go"
    assert os.path.isfile(server_path), f"{server_path} is missing."

    test_file_path = "/home/user/app/test_patch.go"
    cases_path = f"/tmp/verify_cases_{secrets.token_hex(8)}.json"
    test_code = r'''package main

import (
    "encoding/json"
    "fmt"
    "os"
)

type TestCase struct {
    Token  string `json:"token"`
    Secret string `json:"secret"`
}

type TestResult struct {
    HadError bool                   `json:"had_error"`
    Error    string                 `json:"error"`
    Payload  map[string]interface{} `json:"payload"`
}

func main() {
    data, err := os.ReadFile(os.Args[1])
    if err != nil {
        panic(err)
    }
    var cases []TestCase
    if err := json.Unmarshal(data, &cases); err != nil {
        panic(err)
    }

    results := make([]TestResult, 0, len(cases))
    for _, tc := range cases {
        payload, verifyErr := VerifyToken(tc.Token, tc.Secret)
        result := TestResult{Payload: payload}
        if verifyErr != nil {
            result.HadError = true
            result.Error = verifyErr.Error()
        }
        results = append(results, result)
    }

    encoded, err := json.Marshal(results)
    if err != nil {
        panic(err)
    }
    fmt.Println(string(encoded))
}
'''

    cases = []
    expectations = []

    # Retain the original verifier's fixed alg=none assertion.
    fixed_none = "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJyb2xlIjoiYWRtaW4ifQ."
    cases.append({"token": fixed_none, "secret": "secret"})
    expectations.append(("error", None))

    # Exercise independently generated alg=none tokens with varying JSON layout,
    # payloads, signatures, and secrets so rejection cannot target one token.
    for i in range(24):
        marker = secrets.token_hex(10)
        if i % 3 == 0:
            header_text = f'{{ "typ" : "JWT", "nonce" : "{marker}", "alg" : "none" }}'
        elif i % 3 == 1:
            header_text = json.dumps({"alg": "none", "x": marker, "typ": "JWT"}, separators=(",", ":"))
        else:
            header_text = json.dumps({"x": marker, "typ": "JWT", "alg": "none"}, indent=2)
        payload_text = json.dumps(
            {"role": "admin", "marker": marker, "n": secrets.randbelow(1_000_000)},
            separators=(",", ":"),
        )
        signature = "" if i % 2 == 0 else b64url(secrets.token_bytes(12))
        cases.append({
            "token": token(header_text.encode(), payload_text.encode(), signature),
            "secret": secrets.token_hex(16),
        })
        expectations.append(("error", None))

    # Preserve the pre-existing HS256 behavior instead of allowing a reject-all
    # replacement with a generic error.
    for _ in range(10):
        marker = secrets.token_hex(8)
        header = json.dumps({"typ": "JWT", "marker": marker, "alg": "HS256"}).encode()
        payload = secrets.token_bytes(secrets.randbelow(40) + 1)
        cases.append({
            "token": token(header, payload, b64url(secrets.token_bytes(32))),
            "secret": secrets.token_hex(16),
        })
        expectations.append(("exact_error", "signature verification failed"))

    # Preserve unsupported-algorithm handling for varied algorithms, including
    # case variants that are not the exact vulnerable value "none".
    unsupported = ["RS256", "ES256", "None", "NONE", "none ", "HS384", "PS256", ""]
    for alg in unsupported:
        marker = secrets.token_hex(8)
        header = json.dumps({"alg": alg, "typ": "JWT", "marker": marker}, separators=(",", ":")).encode()
        cases.append({
            "token": token(header, secrets.token_bytes(9), b64url(secrets.token_bytes(7))),
            "secret": secrets.token_hex(12),
        })
        expectations.append(("exact_error", "unsupported algorithm"))

    # Preserve the original token-format check and its error.
    malformed = ["", "abc", "a.b", "a.b.c.d", secrets.token_hex(13)]
    for value in malformed:
        cases.append({"token": value, "secret": secrets.token_hex(8)})
        expectations.append(("exact_error", "invalid token format"))

    try:
        with open(test_file_path, "w") as f:
            f.write(test_code)
        with open(cases_path, "w") as f:
            json.dump(cases, f)

        result = subprocess.run(
            ["go", "run", "server.go", "test_patch.go", cases_path],
            cwd="/home/user/app",
            capture_output=True,
            text=True,
            timeout=45,
        )

        assert result.returncode == 0, f"Failed to compile/run server.go with test:\n{result.stderr}"
        output_lines = [line for line in result.stdout.splitlines() if line.strip()]
        assert len(output_lines) == 1, f"Unexpected patch-test output: {result.stdout!r}"
        results = json.loads(output_lines[0])
        assert len(results) == len(expectations), "VerifyToken test harness returned an incomplete result set."

        for index, (actual, expected) in enumerate(zip(results, expectations)):
            kind, value = expected
            assert actual["had_error"], f"VerifyToken accepted forbidden/invalid test case {index}."
            assert actual.get("payload") is None, f"VerifyToken returned a payload on failed test case {index}."
            if kind == "exact_error":
                assert actual["error"] == value, (
                    f"VerifyToken changed existing behavior for case {index}: "
                    f"got {actual['error']!r}, expected {value!r}."
                )
    finally:
        if os.path.exists(test_file_path):
            os.remove(test_file_path)
        if os.path.exists(cases_path):
            os.remove(cases_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
