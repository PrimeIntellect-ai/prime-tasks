#!/bin/bash
set -e
mkdir -p /logs/verifier

reward=0
server_pid=""
test_file="/home/user/audio-svc/parser/verifier_dynamic_test.go"
cleanup() {
    if [ -n "$server_pid" ]; then
        kill "$server_pid" 2>/dev/null || true
        wait "$server_pid" 2>/dev/null || true
    fi
    rm -f "$test_file"
    echo "$reward" > /logs/verifier/reward.txt
}
trap cleanup EXIT

cd /home/user/audio-svc

# Exercise the submitted parser directly on generated inputs. When supported by
# the installed Go toolchain, ASan also detects C buffer errors and leaked C
# allocations when the test process exits.
cat > "$test_file" <<'GO_TEST_EOF'
package parser

import (
    "encoding/binary"
    "os"
    "path/filepath"
    "strings"
    "testing"
)

func writeParserFixture(t *testing.T, path string, id uint32, text string) {
    t.Helper()
    data := []byte("RIFF")
    data = append(data, []byte("generated-wave-data")...)
    data = append(data, []byte("TRNS")...)
    payloadLen := uint32(4 + len(text))
    var word [4]byte
    binary.LittleEndian.PutUint32(word[:], payloadLen)
    data = append(data, word[:]...)
    binary.LittleEndian.PutUint32(word[:], id)
    data = append(data, word[:]...)
    data = append(data, []byte(text)...)
    if err := os.WriteFile(path, data, 0600); err != nil {
        t.Fatal(err)
    }
}

func TestVerifierGeneratedMetadata(t *testing.T) {
    dir := t.TempDir()
    cases := []struct {
        id   uint32
        text string
    }{
        {317, "dynamically generated transcript"},
        {9021, strings.Repeat("safe-buffer-", 257)},
        {77, "a different payload with spaces"},
    }
    for i, tc := range cases {
        path := filepath.Join(dir, string(rune('a'+i))+".wav")
        writeParserFixture(t, path, tc.id, tc.text)
        got := ExtractMetadata(path)
        if got == nil {
            t.Fatalf("ExtractMetadata returned nil for case %d", i)
        }
        if got.ReqID != int(tc.id) || got.RawText != tc.text {
            t.Fatalf("case %d: got id=%d text=%q, want id=%d text=%q", i, got.ReqID, got.RawText, tc.id, tc.text)
        }
    }
}

func TestVerifierTruncatedChunkDoesNotOverrun(t *testing.T) {
    path := filepath.Join(t.TempDir(), "truncated.wav")
    data := []byte("RIFFTRNS")
    var word [4]byte
    binary.LittleEndian.PutUint32(word[:], 12)
    data = append(data, word[:]...)
    binary.LittleEndian.PutUint32(word[:], 55)
    data = append(data, word[:]...)
    data = append(data, 'x')
    if err := os.WriteFile(path, data, 0600); err != nil {
        t.Fatal(err)
    }
    _ = ExtractMetadata(path)
}
GO_TEST_EOF

if go help build 2>&1 | grep -q -- '-asan'; then
    ASAN_OPTIONS='detect_leaks=1:halt_on_error=1' go test -asan -count=1 ./parser
else
    go test -count=1 ./parser
fi
rm -f "$test_file"

go build -o /tmp/audio-svc-submission .

# Do not allow a previously running or hardcoded process to satisfy the tests.
if command -v fuser >/dev/null 2>&1; then
    fuser -k 8080/tcp >/dev/null 2>&1 || true
else
    pkill -9 -x audio-svc 2>/dev/null || true
    pkill -9 -x main 2>/dev/null || true
fi
sleep 0.2
/tmp/audio-svc-submission >/tmp/audio-svc-verifier.log 2>&1 &
server_pid=$!
sleep 0.4
kill -0 "$server_pid"

cat > /tmp/test_final_state.py <<'PY_TEST_EOF'
import json
import os
import random
import re
import secrets
import struct
import time
import wave

import pytest
import requests

URL = "http://127.0.0.1:8080/api/v1/extract"
FIXTURE = "/app/transmission.wav"


def write_fixture(req_id, transcript):
    tmp = FIXTURE + ".verifier-tmp"
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(44100)
        w.writeframes(b"\x00\x00" * random.randint(8, 40))
    encoded = transcript.encode("utf-8")
    payload = struct.pack("<I", req_id) + encoded
    with open(tmp, "ab") as f:
        f.write(b"TRNS" + struct.pack("<I", len(payload)) + payload)
    os.replace(tmp, FIXTURE)


def wait_for_service():
    for _ in range(20):
        try:
            requests.get("http://127.0.0.1:8080/", timeout=1)
            return True
        except requests.exceptions.RequestException:
            time.sleep(0.25)
    return False


@pytest.fixture(scope="session", autouse=True)
def ensure_service_running():
    assert wait_for_service(), "The submitted Go service is not listening on 127.0.0.1:8080."


def assert_schema(response, req_id, transcript):
    assert response.status_code == 200, response.text
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert data.get("transmission_id") == req_id
    assert data.get("transcript") == transcript
    assert data.get("migrated") is True
    assert set(data) == {"transmission_id", "transcript", "migrated"}


def test_extract_old_version_1_0_0():
    write_fixture(104, "Eagle has landed")
    response = requests.post(URL, headers={"X-App-Version": "1.0.0"}, timeout=2)
    assert response.status_code == 426, f"Expected HTTP 426 Upgrade Required for version 1.0.0, got {response.status_code}. Response: {response.text}"


def test_extract_old_version_2_0_9():
    response = requests.post(URL, headers={"X-App-Version": "2.0.9"}, timeout=2)
    assert response.status_code == 426, f"Expected HTTP 426 Upgrade Required for version 2.0.9, got {response.status_code}. Response: {response.text}"


def test_extract_valid_version_2_1_0():
    write_fixture(104, "Eagle has landed")
    response = requests.post(URL, headers={"X-App-Version": "2.1.0"}, timeout=2)
    assert response.status_code == 200, f"Expected HTTP 200 OK for version 2.1.0, got {response.status_code}. Response: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert data.get("transmission_id") == 104
    assert data.get("transcript") == "Eagle has landed"
    assert data.get("migrated") is True


def test_extract_valid_version_2_1_0_beta():
    response = requests.post(URL, headers={"X-App-Version": "2.1.0-beta"}, timeout=2)
    assert response.status_code == 200, f"Expected HTTP 200 OK for version 2.1.0-beta, got {response.status_code}. Response: {response.text}"


def parse_semver(value):
    m = re.fullmatch(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?", value)
    assert m, value
    return (int(m.group(1)), int(m.group(2)), int(m.group(3))), (m.group(4).split(".") if m.group(4) else None)


def compare_identifiers(left, right):
    if left is None and right is None:
        return 0
    if left is None:
        return 1
    if right is None:
        return -1
    for a, b in zip(left, right):
        if a == b:
            continue
        an, bn = a.isdigit(), b.isdigit()
        if an and bn:
            return -1 if int(a) < int(b) else 1
        if an != bn:
            return -1 if an else 1
        return -1 if a < b else 1
    return (len(left) > len(right)) - (len(left) < len(right))


def semver_less(left, right="2.1.0-beta"):
    lc, lp = parse_semver(left)
    rc, rp = parse_semver(right)
    if lc != rc:
        return lc < rc
    return compare_identifiers(lp, rp) < 0


def test_generated_semver_cases_and_live_fixture_parsing():
    token = secrets.token_hex(12)
    req_id = secrets.randbelow(900000) + 1000
    transcript = f"runtime transcript {token}"
    write_fixture(req_id, transcript)

    versions = [
        f"1.{secrets.randbelow(50)}.{secrets.randbelow(500)}",
        f"2.0.{secrets.randbelow(10000)}",
        "2.1.0-alpha",
        f"2.1.0-alpha.{secrets.randbelow(1000)}",
        f"2.1.0-{secrets.randbelow(99)}",
        "2.1.0-beta",
        f"2.1.0-beta.{secrets.randbelow(1000)}",
        "2.1.0-rc.1",
        "2.1.0",
        f"2.1.{secrets.randbelow(1000) + 1}",
        f"2.{secrets.randbelow(50) + 2}.{secrets.randbelow(1000)}",
        f"{secrets.randbelow(20) + 3}.0.0",
        f"2.1.0-beta+{token}",
    ]
    for version in versions:
        response = requests.post(URL, headers={"X-App-Version": version}, timeout=3)
        expected = 426 if semver_less(version) else 200
        assert response.status_code == expected, f"version {version}: expected {expected}, got {response.status_code}: {response.text}"
        if expected == 200:
            assert_schema(response, req_id, transcript)


def test_multiple_unpredictable_wav_payloads_are_parsed_each_request():
    for _ in range(4):
        req_id = secrets.randbelow(2_000_000_000) + 1
        transcript = "generated-" + secrets.token_urlsafe(random.randint(18, 70))
        write_fixture(req_id, transcript)
        response = requests.post(URL, headers={"X-App-Version": "9.7.3"}, timeout=3)
        assert_schema(response, req_id, transcript)
PY_TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short
kill -0 "$server_pid"
reward=1
