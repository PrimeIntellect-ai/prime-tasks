#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat <<'PYTEST_EOF' > /tmp/test_final_state.py
import base64
import collections
import json
import math
import os
import random
import struct
import subprocess
import threading
import wave

import pytest
import requests

URL = "http://127.0.0.1:9000/ingest"


def decode_dtmf(path):
    low = [697, 770, 852, 941]
    high = [1209, 1336, 1477]
    digits = {
        (697, 1209): "1", (697, 1336): "2", (697, 1477): "3",
        (770, 1209): "4", (770, 1336): "5", (770, 1477): "6",
        (852, 1209): "7", (852, 1336): "8", (852, 1477): "9",
        (941, 1336): "0",
    }
    with wave.open(path, "rb") as wav:
        assert wav.getnchannels() == 1
        assert wav.getsampwidth() == 2
        rate = wav.getframerate()
        raw = wav.readframes(wav.getnframes())
    samples = struct.unpack("<%dh" % (len(raw) // 2), raw)
    block = max(1, rate // 100)
    active = []
    for start in range(0, len(samples), block):
        chunk = samples[start:start + block]
        if not chunk:
            continue
        rms = math.sqrt(sum(x * x for x in chunk) / len(chunk))
        active.append(rms > 1000)

    runs = []
    start = None
    for i, is_active in enumerate(active + [False]):
        if is_active and start is None:
            start = i
        elif not is_active and start is not None:
            if i - start >= 5:
                runs.append((start * block, min(i * block, len(samples))))
            start = None

    def power(chunk, freq):
        real = 0.0
        imag = 0.0
        for i, value in enumerate(chunk):
            angle = 2.0 * math.pi * freq * i / rate
            real += value * math.cos(angle)
            imag -= value * math.sin(angle)
        return real * real + imag * imag

    result = []
    for begin, end in runs:
        chunk = samples[begin:end]
        lf = max(low, key=lambda f: power(chunk, f))
        hf = max(high, key=lambda f: power(chunk, f))
        assert (lf, hf) in digits, f"Unrecognized DTMF pair {(lf, hf)}"
        result.append(digits[(lf, hf)])
    assert result, "No DTMF digits were decoded"
    return "".join(result)


def derive_anomaly(path):
    failures = collections.Counter()
    with open(path, "r") as handle:
        for line in handle:
            record = json.loads(line)
            if int(record["status"]) == 500:
                failures[int(record["user_id"])] += 1
    assert failures, "No HTTP 500 records found"
    highest = max(failures.values())
    winners = [uid for uid, count in failures.items() if count == highest]
    assert len(winners) == 1, f"Anomaly is not unique: {winners}"
    return str(winners[0])


INCIDENT_ID = decode_dtmf("/app/alert_log.wav")
AUTH = {"Authorization": f"Bearer {INCIDENT_ID}"}


def test_anomaly_user_file():
    path = "/home/user/anomaly_user.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as handle:
        content = handle.read().strip()
    expected = derive_anomaly("/app/requests.log")
    assert content == expected, f"Expected anomaly user ID {expected!r}, got {content!r}."


def test_go_source_builds_and_stores_decoded_payload_safely():
    source = "/app/ingest/main.go"
    assert os.path.isfile(source), f"Missing Go source: {source}"
    assert not os.path.islink(source), f"Go source must be a regular file: {source}"

    test_path = "/app/ingest/verifier_state_test.go"
    test_source = r'''package main

import (
    "bytes"
    "crypto/rand"
    "encoding/base64"
    "encoding/json"
    "net/http"
    "net/http/httptest"
    "os"
    "sync"
    "testing"
)

func clearVerifierStore(t *testing.T) {
    t.Helper()
    switch store := any(&dataStore).(type) {
    case *map[int]string:
        *store = make(map[int]string)
    case *sync.Map:
        store.Range(func(key, value any) bool {
            store.Delete(key)
            return true
        })
    default:
        t.Fatalf("dataStore is not the supplied map or a sync.Map")
    }
}

func verifierStoredValue(t *testing.T, uid int) (string, bool) {
    t.Helper()
    switch store := any(&dataStore).(type) {
    case *map[int]string:
        value, ok := (*store)[uid]
        return value, ok
    case *sync.Map:
        value, ok := store.Load(uid)
        if !ok {
            return "", false
        }
        text, ok := value.(string)
        if !ok {
            t.Fatalf("stored value for %d is not a string", uid)
        }
        return text, true
    default:
        t.Fatalf("dataStore is not the supplied map or a sync.Map")
        return "", false
    }
}

func invokeVerifierHandler(t *testing.T, uid int, raw []byte, token string) *httptest.ResponseRecorder {
    t.Helper()
    encoded := base64.URLEncoding.EncodeToString(raw)
    body, err := json.Marshal(Payload{UserID: uid, Payload: encoded})
    if err != nil {
        t.Fatal(err)
    }
    req := httptest.NewRequest(http.MethodPost, "/ingest", bytes.NewReader(body))
    req.Header.Set("Content-Type", "application/json")
    if token != "" {
        req.Header.Set("Authorization", "Bearer "+token)
    }
    recorder := httptest.NewRecorder()
    ingestHandler(recorder, req)
    return recorder
}

func TestVerifierURLDecodeStateAndAuth(t *testing.T) {
    token := os.Getenv("VERIFIER_INCIDENT_ID")
    if token == "" {
        t.Fatal("missing verifier incident ID")
    }
    clearVerifierStore(t)

    raw := make([]byte, 41)
    if _, err := rand.Read(raw); err != nil {
        t.Fatal(err)
    }
    raw[0], raw[1] = 0xfb, 0xff // Forces '-' and '_' in Base64URL.
    uid := 700001

    unauthorized := invokeVerifierHandler(t, uid, raw, "")
    if unauthorized.Code != http.StatusUnauthorized {
        t.Fatalf("missing auth returned %d, want 401", unauthorized.Code)
    }
    if _, ok := verifierStoredValue(t, uid); ok {
        t.Fatal("unauthorized request modified dataStore")
    }

    response := invokeVerifierHandler(t, uid, raw, token)
    if response.Code != http.StatusOK {
        t.Fatalf("authorized Base64URL request returned %d: %s", response.Code, response.Body.String())
    }
    value, ok := verifierStoredValue(t, uid)
    if !ok {
        t.Fatal("authorized request did not store its payload")
    }
    if value != string(raw) {
        t.Fatalf("stored payload differs from decoded Base64URL bytes")
    }
}

func TestVerifierConcurrentStateUpdates(t *testing.T) {
    token := os.Getenv("VERIFIER_INCIDENT_ID")
    clearVerifierStore(t)
    const count = 96
    expected := make([][]byte, count)
    var wg sync.WaitGroup
    errors := make(chan string, count)

    for i := 0; i < count; i++ {
        expected[i] = make([]byte, 64)
        if _, err := rand.Read(expected[i]); err != nil {
            t.Fatal(err)
        }
        expected[i][0], expected[i][1] = 0xfb, 0xff
        uid := 710000 + i
        raw := append([]byte(nil), expected[i]...)
        wg.Add(1)
        go func() {
            defer wg.Done()
            response := invokeVerifierHandler(t, uid, raw, token)
            if response.Code != http.StatusOK {
                errors <- response.Body.String()
            }
        }()
    }
    wg.Wait()
    close(errors)
    for message := range errors {
        t.Fatalf("concurrent request failed: %s", message)
    }
    for i := 0; i < count; i++ {
        value, ok := verifierStoredValue(t, 710000+i)
        if !ok || value != string(expected[i]) {
            t.Fatalf("incorrect or missing stored value for user %d", 710000+i)
        }
    }
}
'''
    with open(test_path, "w") as handle:
        handle.write(test_source)
    env = os.environ.copy()
    env["VERIFIER_INCIDENT_ID"] = INCIDENT_ID
    try:
        build = subprocess.run(
            ["go", "build", "-o", "/tmp/verified_ingest", "."],
            cwd="/app/ingest", env=env, text=True, capture_output=True, timeout=90
        )
        assert build.returncode == 0, f"Go service does not build:\n{build.stdout}\n{build.stderr}"
        tested = subprocess.run(
            ["go", "test", "-race", "-count=1", "."],
            cwd="/app/ingest", env=env, text=True, capture_output=True, timeout=120
        )
        assert tested.returncode == 0, f"Go behavioral/race tests failed:\n{tested.stdout}\n{tested.stderr}"
    finally:
        try:
            os.remove(test_path)
        except FileNotFoundError:
            pass


def test_go_service_auth_missing():
    payload = {"user_id": 1, "payload": "SGVsbG8_V29ybGQ="}
    try:
        response = requests.post(URL, json=payload, timeout=2)
        assert response.status_code == 401, f"Expected HTTP 401 for missing auth, got {response.status_code}."
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the Go service: {exc}")


def test_go_service_auth_invalid():
    payload = {"user_id": 1, "payload": "SGVsbG8_V29ybGQ="}
    headers = {"Authorization": "Bearer wrong_token"}
    try:
        response = requests.post(URL, json=payload, headers=headers, timeout=2)
        assert response.status_code == 401, f"Expected HTTP 401 for invalid auth, got {response.status_code}."
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the Go service: {exc}")


def test_go_service_concurrency_and_payload():
    payload = {"user_id": 1, "payload": "SGVsbG8_V29ybGQ="}
    errors = []

    def make_request():
        try:
            response = requests.post(URL, json=payload, headers=AUTH, timeout=5)
            if response.status_code != 200:
                errors.append(f"Expected HTTP 200, got {response.status_code}: {response.text}")
        except Exception as exc:
            errors.append(str(exc))

    threads = [threading.Thread(target=make_request) for _ in range(50)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    assert not errors, f"Errors occurred during concurrent requests: {errors[:5]}"


def test_running_service_accepts_varied_base64url_requests():
    errors = []

    def make_request(index):
        raw = bytes([0xfb, 0xff]) + os.urandom(30) + index.to_bytes(2, "big")
        encoded = base64.urlsafe_b64encode(raw).decode("ascii")
        payload = {"user_id": random.randint(800000, 900000) + index, "payload": encoded}
        try:
            response = requests.post(URL, json=payload, headers=AUTH, timeout=5)
            if response.status_code != 200:
                errors.append(f"request {index}: HTTP {response.status_code}: {response.text}")
        except Exception as exc:
            errors.append(f"request {index}: {exc}")

    threads = [threading.Thread(target=make_request, args=(i,)) for i in range(40)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    assert not errors, f"Varied Base64URL requests failed: {errors[:5]}"


def test_running_service_rejects_malformed_encoding():
    response = requests.post(
        URL,
        json={"user_id": 999991, "payload": "not!base64url"},
        headers=AUTH,
        timeout=3,
    )
    assert response.status_code == 400, f"Malformed Base64URL returned {response.status_code}, want 400"
PYTEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
