#!/bin/bash
mkdir -p /logs/verifier
REAL=/tmp/loc_translator.verifier-real
LOG=/tmp/loc_translator.calls
WRAPPED=0

cleanup() {
    if [ "$WRAPPED" = "1" ] && [ -e "$REAL" ]; then
        rm -f /app/loc_translator
        mv "$REAL" /app/loc_translator
        chmod +x /app/loc_translator
    fi
}
trap cleanup EXIT

if mv /app/loc_translator "$REAL"; then
    WRAPPED=1
else
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'WRAPPER_EOF' > /app/loc_translator
#!/bin/bash
REAL=/tmp/loc_translator.verifier-real
LOG=/tmp/loc_translator.calls
printf 'START|%s|%s|%s|%s\n' "$$" "$(date +%s%N)" "$1" "$2" >> "$LOG"
sleep 0.35
out=$("$REAL" "$@")
status=$?
printf 'END|%s|%s\n' "$$" "$(date +%s%N)" >> "$LOG"
printf '%s' "$out"
exit "$status"
WRAPPER_EOF
chmod +x /app/loc_translator
: > "$LOG"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import collections
import os
import random
import re
import subprocess
import uuid

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090/localize"
SOURCE = "/home/user/server.go"
REAL_TRANSLATOR = "/tmp/loc_translator.verifier-real"
CALL_LOG = "/tmp/loc_translator.calls"


def assert_plain_text(response):
    media_type = response.headers.get("Content-Type", "").split(";", 1)[0].strip().lower()
    assert media_type == "text/plain", f"Expected Content-Type text/plain, got {response.headers.get('Content-Type')!r}"


def test_required_go_artifact_and_constructs():
    assert os.path.isfile(SOURCE), f"Missing required Go source: {SOURCE}"
    with open(SOURCE, "r", encoding="utf-8") as f:
        source = f.read()

    assert re.search(r'["`]text/template["`]', source), "server.go must import text/template"
    assert re.search(r'\b(Parse|ParseFiles|ParseGlob|Execute|ExecuteTemplate)\s*\(', source), \
        "server.go must parse and execute a template"
    assert re.search(r'\bgo\s+(?:func\s*\(|[A-Za-z_])', source), \
        "server.go must launch translation work with goroutines"
    assert "/app/loc_translator" in source, "server.go must invoke /app/loc_translator"

    build = subprocess.run(
        ["go", "build", "-o", "/tmp/server-verifier-build", SOURCE],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert build.returncode == 0, f"server.go does not compile:\n{build.stdout}"


def test_localize_es_es():
    payload = {
        "locale": "es-ES",
        "start_time": 1000,
        "end_time": 1030,
        "interval": 10,
        "events": {"1000": "Welcome", "1030": "Error"}
    }
    try:
        response = requests.post(BASE_URL, json=payload, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}: {e}")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}. Response: {response.text}"
    assert_plain_text(response)
    expected_lines = [
        "[1000] Bienvenido",
        "[1010] Inactivo",
        "[1020] Inactivo",
        "[1030] Error"
    ]
    actual_lines = response.text.strip().split("\n")
    assert actual_lines == expected_lines, f"Expected {expected_lines}, got {actual_lines}"


def test_localize_fr_fr():
    payload = {
        "locale": "fr-FR",
        "start_time": 2000,
        "end_time": 2010,
        "interval": 10,
        "events": {"2010": "Warning"}
    }
    try:
        response = requests.post(BASE_URL, json=payload, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}: {e}")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}. Response: {response.text}"
    assert_plain_text(response)
    expected_lines = [
        "[2000] Inactif",
        "[2010] Avertissement"
    ]
    actual_lines = response.text.strip().split("\n")
    assert actual_lines == expected_lines, f"Expected {expected_lines}, got {actual_lines}"


def test_localize_invalid_locale():
    payload = {
        "locale": "de-DE",
        "start_time": 3000,
        "end_time": 3010,
        "interval": 10,
        "events": {}
    }
    try:
        response = requests.post(BASE_URL, json=payload, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {BASE_URL}: {e}")

    assert response.status_code == 400, f"Expected status 400 for invalid locale, got {response.status_code}. Response: {response.text}"


def oracle(locale, text):
    encoded = base64.b64encode(text.encode()).decode()
    result = subprocess.run(
        [REAL_TRANSLATOR, locale, encoded], check=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=3
    )
    return result.stdout


def test_randomized_resampling_binary_invocation_and_parallelism():
    rng = random.SystemRandom()
    locale = rng.choice(["es-ES", "fr-FR"])
    interval = rng.choice([3, 7, 11, 13])
    start = rng.randrange(100000, 900000)
    timestamps = [start + i * interval for i in range(10)]
    gap_index = rng.randrange(1, 9)

    supplied = ["Welcome", "Warning", "Error"] + [
        "probe-" + uuid.uuid4().hex for _ in range(6)
    ]
    rng.shuffle(supplied)
    events = {}
    expected_inputs = []
    supplied_index = 0
    for i, timestamp in enumerate(timestamps):
        if i == gap_index:
            text = "Idle"
        else:
            text = supplied[supplied_index]
            supplied_index += 1
            events[str(timestamp)] = text
        expected_inputs.append(text)

    payload = {
        "locale": locale,
        "start_time": timestamps[0],
        "end_time": timestamps[-1],
        "interval": interval,
        "events": events,
    }
    expected_lines = [
        f"[{timestamp}] {oracle(locale, text)}"
        for timestamp, text in zip(timestamps, expected_inputs)
    ]

    open(CALL_LOG, "w").close()
    response = requests.post(BASE_URL, json=payload, timeout=10)
    assert response.status_code == 200, f"Expected status 200, got {response.status_code}. Response: {response.text}"
    assert_plain_text(response)
    assert response.text.strip().split("\n") == expected_lines

    with open(CALL_LOG, "r", encoding="utf-8") as f:
        records = [line.strip().split("|") for line in f if line.strip()]

    starts = [record for record in records if record[0] == "START"]
    actual_calls = collections.Counter((record[3], record[4]) for record in starts)
    expected_calls = collections.Counter(
        (locale, base64.b64encode(text.encode()).decode()) for text in expected_inputs
    )
    assert actual_calls == expected_calls, \
        f"Expected one translator invocation per timeline value; expected {expected_calls}, got {actual_calls}"

    first_end = next((i for i, record in enumerate(records) if record[0] == "END"), len(records))
    starts_before_first_end = sum(1 for record in records[:first_end] if record[0] == "START")
    assert starts_before_first_end >= 2, "Translator invocations were not performed in parallel"

    invalid = {
        "locale": "invalid-" + uuid.uuid4().hex,
        "start_time": start,
        "end_time": start + interval,
        "interval": interval,
        "events": {},
    }
    invalid_response = requests.post(BASE_URL, json=invalid, timeout=5)
    assert invalid_response.status_code == 400
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
