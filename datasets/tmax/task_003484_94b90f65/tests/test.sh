#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import pytest


def test_crash_payload_file():
    payload_file = "/home/user/crash_payload.txt"
    assert os.path.isfile(payload_file), f"File {payload_file} does not exist."

    with open(payload_file, "r") as f:
        content = f.read().strip()

    expected_payload = "0301f10a0b0c0d0e"
    assert content == expected_payload, f"Expected crash payload '{expected_payload}', but got '{content}'"


def test_parser_go_fixed():
    parser_file = "/home/user/project/parser.go"
    assert os.path.isfile(parser_file), f"File {parser_file} does not exist."

    with open(parser_file, "r") as f:
        content = f.read()

    # Preserve the original source-level assertion.
    assert "invalid length" in content, "The error message 'invalid length' was not found in parser.go"


def test_parse_packet_behavior():
    project_dir = "/home/user/project"
    assert os.path.isdir(project_dir), f"Directory {project_dir} does not exist."

    verifier_test = os.path.join(project_dir, "zz_verifier_behavior_test.go")
    source = r'''package parser

import (
    "bytes"
    crand "crypto/rand"
    "encoding/binary"
    "testing"
)

func verifierRandomBytes(t *testing.T, n int) []byte {
    t.Helper()
    b := make([]byte, n)
    if n > 0 {
        if _, err := crand.Read(b); err != nil {
            t.Fatalf("could not generate test input: %v", err)
        }
    }
    return b
}

func TestVerifierParsePacketBehavior(t *testing.T) {
    // Valid packets must return the encoded type and exactly the encoded value.
    lengths := []int{0, 1, 2, 17, 255, 256, 500, 4096, 65535}
    for _, n := range lengths {
        typ := verifierRandomBytes(t, 1)[0]
        value := verifierRandomBytes(t, n)
        packet := make([]byte, 3+n+3)
        packet[0] = typ
        binary.BigEndian.PutUint16(packet[1:3], uint16(n))
        copy(packet[3:], value)
        copy(packet[3+n:], verifierRandomBytes(t, 3))

        gotType, gotValue, err := ParsePacket(packet)
        if err != nil {
            t.Fatalf("valid packet of length %d returned error: %v", n, err)
        }
        if gotType != typ {
            t.Fatalf("valid packet type: got %02x, want %02x", gotType, typ)
        }
        if !bytes.Equal(gotValue, value) {
            t.Fatalf("valid packet of length %d returned the wrong value", n)
        }
    }

    // Exercise additional inputs generated at verification time.
    for i := 0; i < 200; i++ {
        sizeBytes := verifierRandomBytes(t, 2)
        n := int(binary.BigEndian.Uint16(sizeBytes)) % 2049
        trailing := int(verifierRandomBytes(t, 1)[0] % 8)
        typ := verifierRandomBytes(t, 1)[0]
        value := verifierRandomBytes(t, n)
        packet := make([]byte, 3+n+trailing)
        packet[0] = typ
        binary.BigEndian.PutUint16(packet[1:3], uint16(n))
        copy(packet[3:], value)
        copy(packet[3+n:], verifierRandomBytes(t, trailing))

        gotType, gotValue, err := ParsePacket(packet)
        if err != nil || gotType != typ || !bytes.Equal(gotValue, value) {
            t.Fatalf("random valid packet parsed incorrectly: type=%02x length=%d err=%v", typ, n, err)
        }
    }

    // Every encoded length larger than the available value must return the
    // required error rather than succeeding or panicking.
    for i := 0; i < 250; i++ {
        random := verifierRandomBytes(t, 3)
        available := int(random[0] % 97)
        claimed := available + 1 + int(random[1])
        packet := make([]byte, 3+available)
        packet[0] = random[2]
        binary.BigEndian.PutUint16(packet[1:3], uint16(claimed))
        copy(packet[3:], verifierRandomBytes(t, available))

        _, _, err := ParsePacket(packet)
        if err == nil {
            t.Fatalf("malformed packet with claimed=%d available=%d returned no error", claimed, available)
        }
        if err.Error() != "invalid length" {
            t.Fatalf("malformed packet returned %q, want %q", err.Error(), "invalid length")
        }
    }

    boundary := []byte{0x03, 0xff, 0xff, 0x0a, 0x0b, 0x0c}
    _, _, err := ParsePacket(boundary)
    if err == nil || err.Error() != "invalid length" {
        t.Fatalf("65535-byte malformed length returned %v, want invalid length", err)
    }
}
'''

    with open(verifier_test, "w") as f:
        f.write(source)

    try:
        try:
            result = subprocess.run(
                ["go", "test", "-count=1", "-run", "^TestVerifierParsePacketBehavior$"],
                cwd=project_dir,
                capture_output=True,
                text=True,
                timeout=30,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("Behavioral parser tests timed out after 30 seconds.")
        except FileNotFoundError:
            pytest.fail("The 'go' command was not found.")

        assert result.returncode == 0, (
            f"Behavioral parser tests failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
    finally:
        try:
            os.remove(verifier_test)
        except FileNotFoundError:
            pass


def test_go_fuzz_tests_pass():
    project_dir = "/home/user/project"
    assert os.path.isdir(project_dir), f"Directory {project_dir} does not exist."

    try:
        result = subprocess.run(
            ["go", "test", "-fuzz=FuzzParsePacket", "-fuzztime=2s"],
            cwd=project_dir,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Go fuzz tests timed out after 30 seconds.")
    except FileNotFoundError:
        pytest.fail("The 'go' command was not found.")

    assert result.returncode == 0, f"Go fuzz tests failed.\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    assert "ok" in result.stdout or "PASS" in result.stdout, "Fuzz tests did not output 'ok' or 'PASS'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
