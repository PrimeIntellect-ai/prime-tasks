#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import socket
import subprocess
import time
import urllib.error
import urllib.request
import uuid

RESULT = "/home/user/result.json"
AUDIT = "/home/user/app/audit.log"
DECRYPTER = "/home/user/decrypt_log.go"
HELPER_SRC = "/tmp/audit_helper.go"
HELPER_BIN = "/tmp/audit_helper"
APP_BIN = "/tmp/app_under_test"

HELPER_CODE = r'''package main
import (
    "bufio"
    "crypto/aes"
    "crypto/cipher"
    "crypto/rand"
    "encoding/base64"
    "encoding/json"
    "fmt"
    "io"
    "os"
)
var key = []byte("supersecret32bytekey123456789012")
func main() {
    if len(os.Args) < 3 { os.Exit(2) }
    block, err := aes.NewCipher(key)
    if err != nil { panic(err) }
    gcm, err := cipher.NewGCM(block)
    if err != nil { panic(err) }
    switch os.Args[1] {
    case "decrypt":
        f, err := os.Open(os.Args[2])
        if err != nil { panic(err) }
        defer f.Close()
        scanner := bufio.NewScanner(f)
        for scanner.Scan() {
            if scanner.Text() == "" { continue }
            raw, err := base64.StdEncoding.DecodeString(scanner.Text())
            if err != nil || len(raw) < gcm.NonceSize() { continue }
            plain, err := gcm.Open(nil, raw[:gcm.NonceSize()], raw[gcm.NonceSize():], nil)
            if err == nil { fmt.Println(string(plain)) }
        }
        if err := scanner.Err(); err != nil { panic(err) }
    case "encrypt":
        nonce := make([]byte, gcm.NonceSize())
        if _, err := io.ReadFull(rand.Reader, nonce); err != nil { panic(err) }
        entry := map[string]interface{}{
            "timestamp": int64(1700000000),
            "action": "credential_rotation",
            "rotation_id": os.Args[2],
            "new_cred_hash": "hash_placeholder",
        }
        plain, err := json.Marshal(entry)
        if err != nil { panic(err) }
        sealed := gcm.Seal(nonce, nonce, plain, nil)
        fmt.Println(base64.StdEncoding.EncodeToString(sealed))
    default:
        os.Exit(2)
    }
}
'''

def read_result():
    assert os.path.isfile(RESULT), "/home/user/result.json does not exist"
    with open(RESULT, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "/home/user/result.json is not valid JSON"
    assert "crafted_jwt" in data, "Missing crafted_jwt in result.json"
    assert "rotation_id" in data, "Missing rotation_id in result.json"
    assert isinstance(data["crafted_jwt"], str), "crafted_jwt must be a string"
    assert isinstance(data["rotation_id"], str), "rotation_id must be a string"
    assert data["rotation_id"], "rotation_id must not be empty"
    return data

def ensure_helper():
    if os.path.isfile(HELPER_BIN):
        return
    with open(HELPER_SRC, "w") as f:
        f.write(HELPER_CODE)
    res = subprocess.run(["go", "build", "-o", HELPER_BIN, HELPER_SRC], capture_output=True, text=True)
    assert res.returncode == 0, "Failed to build Go audit helper: " + res.stderr

def trusted_events(path=AUDIT):
    ensure_helper()
    res = subprocess.run([HELPER_BIN, "decrypt", path], capture_output=True, text=True)
    assert res.returncode == 0, "Failed to run Go decryption helper"
    events = []
    for line in res.stdout.splitlines():
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            events.append(value)
    return events, res.stdout

def run_submitted_decrypter():
    assert os.path.isfile(DECRYPTER), "/home/user/decrypt_log.go does not exist"
    assert os.path.isfile(DECRYPTER) and not os.path.islink(DECRYPTER), "decrypt_log.go must be a regular file"
    try:
        return subprocess.run(
            ["go", "run", DECRYPTER],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        assert False, "decrypt_log.go timed out"

def test_result_json_exists_and_valid():
    read_result()

def test_crafted_jwt():
    data = read_result()
    jwt = data["crafted_jwt"]
    parts = jwt.split(".")
    assert len(parts) == 3, "JWT must have exactly 3 parts separated by dots"

    def decode_b64(s):
        s = s.replace("-", "+").replace("_", "/")
        s += "=" * ((4 - len(s) % 4) % 4)
        return base64.b64decode(s)

    try:
        header = json.loads(decode_b64(parts[0]))
        payload = json.loads(decode_b64(parts[1]))
    except Exception as e:
        assert False, f"Failed to decode JWT header or payload: {e}"

    assert header.get("alg") == "none", "JWT header 'alg' must be 'none'"
    assert payload.get("role") == "admin", "JWT payload 'role' must be 'admin'"

def test_rotation_id_matches_log():
    assert os.path.isfile(AUDIT), "/home/user/app/audit.log does not exist"
    assert os.path.getsize(AUDIT) > 0, "/home/user/app/audit.log is empty"
    expected_id = read_result()["rotation_id"]
    events, decrypted_logs = trusted_events()

    # Preserve the original assertion while also requiring an exact, structured entry.
    assert expected_id in decrypted_logs, f"Rotation ID '{expected_id}' from result.json was not found in the decrypted audit logs."
    matches = [e for e in events if e.get("rotation_id") == expected_id]
    assert matches, "The reported rotation_id does not exactly match a decrypted JSON audit entry"
    assert any(e.get("action") == "credential_rotation" for e in matches), "Matching audit entry has the wrong action"
    assert any(isinstance(e.get("timestamp"), int) and e["timestamp"] > 0 for e in matches), "Matching audit entry has an invalid timestamp"

def test_submitted_decryptor_on_real_and_derived_log():
    expected_id = read_result()["rotation_id"]
    original = open(AUDIT, "rb").read()

    real = run_submitted_decrypter()
    assert real.returncode == 0, "decrypt_log.go failed on the real audit log: " + real.stderr
    assert expected_id in real.stdout, "decrypt_log.go did not extract the reported rotation_id from the real audit log"

    ensure_helper()
    challenge_id = "ROT-VERIFY-" + uuid.uuid4().hex
    enc = subprocess.run([HELPER_BIN, "encrypt", challenge_id], capture_output=True, text=True)
    assert enc.returncode == 0, "Failed to generate verifier audit fixture"
    try:
        with open(AUDIT, "w") as f:
            f.write(enc.stdout.strip() + "\n")
        challenged = run_submitted_decrypter()
        assert challenged.returncode == 0, "decrypt_log.go failed on a valid verifier-generated audit log: " + challenged.stderr
        assert challenge_id in challenged.stdout, "decrypt_log.go did not decrypt and extract a verifier-generated rotation_id"
    finally:
        with open(AUDIT, "wb") as f:
            f.write(original)

def port_open():
    try:
        with socket.create_connection(("127.0.0.1", 8080), timeout=0.3):
            return True
    except OSError:
        return False

def test_endpoint_accepts_reported_exploit_and_required_credential():
    data = read_result()

    build = subprocess.run(
        ["go", "build", "-o", APP_BIN, "/home/user/app/main.go"],
        cwd="/home/user/app",
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, "The Go application does not build: " + build.stderr

    proc = None
    if not port_open():
        proc = subprocess.Popen([APP_BIN], cwd="/home/user/app", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.time() + 10
        while time.time() < deadline and not port_open():
            if proc.poll() is not None:
                break
            time.sleep(0.1)
        assert port_open(), "The Go application did not start on port 8080"

    before_bytes = open(AUDIT, "rb").read()
    before_events, _ = trusted_events()
    body = json.dumps({"new_credential": "SECURE_ROTATED_CRED_2024"}).encode()
    request = urllib.request.Request(
        "http://127.0.0.1:8080/admin/rotate",
        data=body,
        method="POST",
        headers={
            "Authorization": "Bearer " + data["crafted_jwt"],
            "Content-Type": "application/json",
        },
    )
    try:
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                status = response.status
                response.read()
        except urllib.error.HTTPError as e:
            status = e.code
            e.read()
        assert status == 200, f"POST /admin/rotate rejected the reported JWT or required credential with HTTP {status}"

        after_bytes = open(AUDIT, "rb").read()
        assert len(after_bytes) > len(before_bytes), "The rotation endpoint did not append an audit entry"
        assert after_bytes.startswith(before_bytes), "The rotation endpoint did not append to the existing audit log"

        after_events, _ = trusted_events()
        assert len(after_events) > len(before_events), "No new decryptable JSON audit entry was produced by the endpoint"
        new_events = after_events[len(before_events):]
        assert any(
            e.get("action") == "credential_rotation"
            and isinstance(e.get("rotation_id"), str)
            and e.get("rotation_id")
            for e in new_events
        ), "The endpoint's new audit entry is not a valid credential rotation event"
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
