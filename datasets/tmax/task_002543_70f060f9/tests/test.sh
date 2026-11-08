#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

INVESTIGATION = "/home/user/investigation"


def derive_plaintext():
    """Independently extract an AES256Key candidate and decrypt the supplied artifact."""
    helper = r'''
package main

import (
    "bytes"
    "crypto/aes"
    "crypto/cipher"
    "fmt"
    "os"
)

func main() {
    malware, err := os.ReadFile("/home/user/investigation/malware.bin")
    if err != nil { panic(err) }
    encrypted, err := os.ReadFile("/home/user/investigation/exfil_data.enc")
    if err != nil { panic(err) }

    prefix := []byte("AES256Key")
    for start := 0; start < len(malware); {
        rel := bytes.Index(malware[start:], prefix)
        if rel < 0 { break }
        pos := start + rel
        if pos + 32 <= len(malware) {
            key := malware[pos:pos+32]
            block, err := aes.NewCipher(key)
            if err == nil {
                gcm, err := cipher.NewGCM(block)
                if err == nil && len(encrypted) >= gcm.NonceSize()+gcm.Overhead() {
                    nonce := encrypted[:gcm.NonceSize()]
                    ciphertext := encrypted[gcm.NonceSize():]
                    plaintext, err := gcm.Open(nil, nonce, ciphertext, nil)
                    if err == nil {
                        if err := os.WriteFile("/tmp/derived_plaintext.log", plaintext, 0600); err != nil {
                            panic(err)
                        }
                        return
                    }
                }
            }
        }
        start = pos + 1
    }
    panic(fmt.Errorf("no embedded 32-byte AES256Key candidate decrypted exfil_data.enc"))
}
'''
    with open("/tmp/derive_plaintext.go", "w") as f:
        f.write(helper)
    result = subprocess.run(
        ["go", "run", "/tmp/derive_plaintext.go"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, "independent artifact decryption failed: " + result.stderr.decode(errors="replace")
    with open("/tmp/derived_plaintext.log", "rb") as f:
        return f.read()


def test_decrypted_log():
    """Verify decrypted.log exactly matches an independent decryption of exfil_data.enc."""
    log_path = os.path.join(INVESTIGATION, "decrypted.log")
    assert os.path.isfile(log_path), f"File not found: {log_path}"

    with open(log_path, "rb") as f:
        actual = f.read()
    expected = derive_plaintext()
    assert actual == expected, "decrypted.log is not the exact authenticated plaintext of exfil_data.enc"

    # Preserve the original known-record assertions as an additional integrity check.
    content = actual.decode("utf-8")
    expected_lines = [
        "2024-05-10T12:00:00Z | exfil_success | IP: 192.168.1.55 | bytes: 1024",
        "2024-05-10T12:05:00Z | exfil_failed | IP: 10.0.0.1 | bytes: 0",
        "2024-05-10T12:10:00Z | exfil_success | IP: 203.0.113.42 | bytes: 5000",
        "2024-05-10T12:15:00Z | login_attempt | IP: 192.168.1.55 | bytes: 0",
        "2024-05-10T12:20:00Z | exfil_success | IP: 192.168.1.55 | bytes: 2048",
        "2024-05-10T12:25:00Z | exfil_success | IP: 198.51.100.7 | bytes: 128",
    ]
    for line in expected_lines:
        assert line in content, f"Expected line missing from decrypted.log: {line}"


def test_attacker_ips():
    """Derive the required sorted unique IP list from the authenticated plaintext."""
    ips_path = os.path.join(INVESTIGATION, "attacker_ips.txt")
    assert os.path.isfile(ips_path), f"File not found: {ips_path}"

    with open(ips_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_ips = ["192.168.1.55", "198.51.100.7", "203.0.113.42"]
    assert sorted(lines) == sorted(expected_ips), f"Expected IPs {expected_ips}, but got {lines}"

    plaintext = derive_plaintext().decode("utf-8")
    derived = set()
    for line in plaintext.splitlines():
        parts = line.split(" | ")
        assert len(parts) == 4, f"Unexpected decrypted log format: {line!r}"
        if parts[1] == "exfil_success":
            assert parts[2].startswith("IP: "), f"Unexpected IP field: {parts[2]!r}"
            derived.add(parts[2][4:])
    assert lines == sorted(derived), "attacker_ips.txt is not the sorted unique result parsed from decrypted.log"


def request(filename):
    query = urllib.parse.urlencode({"file": filename})
    req = urllib.request.Request("http://127.0.0.1:8080/download?" + query)
    try:
        with urllib.request.urlopen(req, timeout=2) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def wait_for_server(proc):
    deadline = time.time() + 5
    while time.time() < deadline:
        assert proc.poll() is None, "server process exited before accepting requests"
        try:
            request("")
            return
        except urllib.error.URLError:
            time.sleep(0.05)
    raise AssertionError("server did not start listening on port 8080")


def exercise_server(binary_path):
    token = secrets.token_hex(12)
    uploads = "/var/www/uploads"
    nested = os.path.join(uploads, "nested_" + token)
    os.makedirs(nested, exist_ok=True)

    fixed_file = os.path.join(uploads, "test_valid.txt")
    random_name = "valid_" + token + ".txt"
    random_file = os.path.join(uploads, random_name)
    nested_name = "nested_" + token + "/data.txt"
    nested_file = os.path.join(uploads, nested_name)
    outside_name = "outside_" + token + ".txt"
    outside_file = os.path.join("/var/www", outside_name)
    sibling_dir = os.path.join("/var/www", "uploads_evil_" + token)
    sibling_file = os.path.join(sibling_dir, "secret.txt")

    os.makedirs(sibling_dir, exist_ok=True)
    fixtures = {
        fixed_file: b"VALID_CONTENT",
        random_file: ("RANDOM_VALID_" + secrets.token_hex(20)).encode(),
        nested_file: ("NESTED_VALID_" + secrets.token_hex(20)).encode(),
        outside_file: ("OUTSIDE_SECRET_" + secrets.token_hex(20)).encode(),
        sibling_file: ("SIBLING_SECRET_" + secrets.token_hex(20)).encode(),
    }
    for path, data in fixtures.items():
        with open(path, "wb") as f:
            f.write(data)

    proc = subprocess.Popen([binary_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wait_for_server(proc)

        # Preserve the original fixed valid-file assertion.
        status, body = request("test_valid.txt")
        assert status == 200, "Valid request did not return 200 OK"
        assert body == b"VALID_CONTENT", "Valid request did not return correct file content"

        # Unpredictable valid files ensure the executable actually serves from uploads.
        for name, expected_body in [(random_name, fixtures[random_file]), (nested_name, fixtures[nested_file])]:
            status, body = request(name)
            assert status == 200, f"Valid request for {name!r} returned {status}"
            assert body == expected_body, f"Valid request for {name!r} returned incorrect content"

        # Preserve the original traversal assertion.
        status, body = request("../../../../etc/passwd")
        assert status in (400, 403, 404), f"Path traversal returned {status}, expected 400, 403, or 404"

        traversals = [
            "../" + outside_name,
            "nested_" + token + "/../../" + outside_name,
            "../uploads_evil_" + token + "/secret.txt",
            "..//" + outside_name,
        ]
        forbidden_bodies = {fixtures[outside_file], fixtures[sibling_file]}
        for value in traversals:
            status, body = request(value)
            assert status in (400, 403, 404), f"Traversal {value!r} returned {status}"
            assert body not in forbidden_bodies, f"Traversal {value!r} disclosed an outside file"

        status, _ = request("missing_" + token)
        assert status in (400, 403, 404), "Invalid file did not return 400, 403, or 404"
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)
        for path in fixtures:
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        for directory in (nested, sibling_dir):
            try:
                os.rmdir(directory)
            except OSError:
                pass


def test_server_patched_execution():
    """Run both the submitted executable and a fresh build of the patched server.go."""
    binary_path = os.path.join(INVESTIGATION, "server_patched")
    source_path = os.path.join(INVESTIGATION, "server.go")
    assert os.path.isfile(binary_path), f"File not found: {binary_path}"
    assert os.access(binary_path, os.X_OK), f"File is not executable: {binary_path}"
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "server_patched is not a compiled ELF executable"

    exercise_server(binary_path)

    assert os.path.isfile(source_path), f"File not found: {source_path}"
    rebuilt = "/tmp/server_rebuilt_" + secrets.token_hex(8)
    result = subprocess.run(
        ["go", "build", "-o", rebuilt, source_path],
        cwd=INVESTIGATION,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, "patched server.go does not compile: " + result.stderr.decode(errors="replace")
    try:
        exercise_server(rebuilt)
    finally:
        try:
            os.remove(rebuilt)
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
