#!/bin/bash
set -e
mkdir -p /logs/verifier

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

cat << 'GO_EOF' > "$TEST_DIR/validator.go"
package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

type Header struct {
	Alg string `json:"alg"`
}

type Payload struct {
	User string `json:"user"`
	Role string `json:"role"`
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: validator <token>")
		return
	}
	token := os.Args[1]
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		fmt.Println("Invalid token format")
		return
	}

	headerBytes, err1 := base64.RawURLEncoding.DecodeString(parts[0])
	payloadBytes, err2 := base64.RawURLEncoding.DecodeString(parts[1])
	if err1 != nil || err2 != nil {
		fmt.Println("Invalid encoding")
		return
	}
	signature := parts[2]

	var header Header
	if err := json.Unmarshal(headerBytes, &header); err != nil {
		fmt.Println("Invalid header JSON")
		return
	}

	// Vulnerability: accepts "none" algorithm to bypass signature verification
	if header.Alg != "none" {
		mac := hmac.New(sha256.New, []byte("super_secret_unpredictable_key_999"))
		mac.Write([]byte(parts[0] + "." + parts[1]))
		expectedMAC := mac.Sum(nil)
		expectedSignature := base64.RawURLEncoding.EncodeToString(expectedMAC)
		if signature != expectedSignature {
			fmt.Println("Invalid signature")
			return
		}
	} else {
		if signature != "" {
			fmt.Println("Invalid signature for none alg")
			return
		}
	}

	var payload Payload
	if err := json.Unmarshal(payloadBytes, &payload); err != nil {
		fmt.Println("Invalid payload JSON")
		return
	}

	if payload.Role == "admin" && payload.User == "system_admin" {
		fmt.Println("Access Granted: Admin")
	} else {
		fmt.Println("Access Granted: User")
	}
}
GO_EOF

cat << 'TEST_EOF' > "$TEST_DIR/test_final_state.py"
import os
import subprocess

PAYLOAD_PATH = "/home/user/payload.txt"
VALIDATOR_PATH = "/home/user/validator.go"
TRUSTED_VALIDATOR_PATH = os.environ["TRUSTED_VALIDATOR_PATH"]


def test_payload_exists():
    """Verify that the payload file exists."""
    assert os.path.isfile(PAYLOAD_PATH), f"File {PAYLOAD_PATH} is missing."


def test_payload_works():
    """Verify the supplied validator is unchanged and the token grants admin access."""
    assert os.path.isfile(PAYLOAD_PATH), f"{PAYLOAD_PATH} must exist to run the test."
    assert os.path.isfile(VALIDATOR_PATH), f"{VALIDATOR_PATH} must exist to run the test."

    with open(VALIDATOR_PATH, "rb") as supplied, open(TRUSTED_VALIDATOR_PATH, "rb") as trusted:
        assert supplied.read() == trusted.read(), f"{VALIDATOR_PATH} was modified."

    with open(PAYLOAD_PATH, "r") as f:
        token = f.read().strip()

    assert token, f"{PAYLOAD_PATH} is empty."

    result = subprocess.run(
        ["go", "run", TRUSTED_VALIDATOR_PATH, token],
        capture_output=True,
        text=True,
        timeout=30,
    )

    assert result.returncode == 0, f"Validator script crashed or failed to compile: {result.stderr}"
    assert "Access Granted: Admin" in result.stdout, f"Token failed to grant admin access. Output was: {result.stdout.strip()}"
TEST_EOF

export TRUSTED_VALIDATOR_PATH="$TEST_DIR/validator.go"
if python3 -m pytest "$TEST_DIR/test_final_state.py" -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
