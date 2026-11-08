#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import csv
import os
import re
import signal
import socket
import subprocess
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime

RAW = "/home/user/data/loc_events.csv"
TSV = "/home/user/processed/wide_events.tsv"
SERVER_DIR = "/home/user/server"
AUTH = {"Authorization": "Bearer loc-eng-token"}


def request(event_id, lang, headers=None):
    query = urllib.parse.urlencode({"event_id": event_id, "lang": lang})
    req = urllib.request.Request(
        "http://127.0.0.1:8080/timeline?" + query,
        headers=headers or {},
    )
    try:
        with urllib.request.urlopen(req, timeout=3) as response:
            return response.status, response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8")


def parse_time(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def expected_wide_rows():
    with open(RAW, newline="", encoding="utf-8") as handle:
        source = list(csv.DictReader(handle))
    assert source, "Raw localization CSV is empty"
    assert set(source[0]) == {"timestamp", "event_id", "lang_code", "raw_text", "translated_text"}

    latest = {}
    for row in source:
        key = (row["event_id"], row["lang_code"])
        normalized = dict(row)
        normalized["translated_text"] = unicodedata.normalize("NFC", row["translated_text"])
        if key not in latest or parse_time(normalized["timestamp"]) >= parse_time(latest[key]["timestamp"]):
            latest[key] = normalized

    events = {}
    for (event_id, lang), row in latest.items():
        event = events.setdefault(event_id, {"timestamp": row["timestamp"], "event_id": event_id})
        if parse_time(row["timestamp"]) > parse_time(event["timestamp"]):
            event["timestamp"] = row["timestamp"]
        if lang in {"en", "es", "fr", "zh"}:
            event[lang] = row["translated_text"]

    result = []
    for event in events.values():
        result.append([
            event["timestamp"], event["event_id"],
            event.get("en", "MISSING"), event.get("es", "MISSING"),
            event.get("fr", "MISSING"), event.get("zh", "MISSING"),
        ])
    result.sort(key=lambda row: (parse_time(row[0]), row[1]))
    return result


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as handle:
                next(handle)
                for line in handle:
                    fields = line.split()
                    if int(fields[1].rsplit(":", 1)[1], 16) == port and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    pids.add(int(name))
        except (FileNotFoundError, PermissionError):
            pass
    return pids


def stop_port(port):
    for pid in listener_pids(port):
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 3
    while listener_pids(port) and time.time() < deadline:
        time.sleep(0.05)
    for pid in listener_pids(port):
        os.kill(pid, signal.SIGKILL)


# Preserve the original verifier's package assertion, then actually compile and call it.
times_go = "/app/go-humanize/times.go"
assert os.path.isfile(times_go), f"File missing: {times_go}"
with open(times_go, encoding="utf-8") as handle:
    times_content = handle.read()
assert 'return "just now"' in times_content, "The syntax error in times.go does not appear to be fixed."
subprocess.run(
    ["go", "test", "./..."], cwd="/app/go-humanize", check=True,
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30,
)
check_dir = "/tmp/check-humanize"
os.makedirs(check_dir, exist_ok=True)
with open(os.path.join(check_dir, "go.mod"), "w", encoding="utf-8") as handle:
    handle.write("module verifier/check\n\ngo 1.18\n\nrequire github.com/dustin/go-humanize v0.0.0\nreplace github.com/dustin/go-humanize => /app/go-humanize\n")
with open(os.path.join(check_dir, "main.go"), "w", encoding="utf-8") as handle:
    handle.write('package main\nimport ("fmt"; "time"; humanize "github.com/dustin/go-humanize")\nfunc main(){fmt.Print(humanize.Time(time.Now()))}\n')
called = subprocess.run(
    ["go", "run", "."], cwd=check_dir, check=True,
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30,
).stdout
assert called == "just now", f"Unexpected go-humanize Time behavior: {called!r}"

# Derive the complete expected transformation from the raw CSV.
assert os.path.isfile(TSV), f"File missing: {TSV}"
with open(TSV, newline="", encoding="utf-8") as handle:
    actual = list(csv.reader(handle, delimiter="\t"))
expected_header = ["timestamp", "event_id", "en", "es", "fr", "zh"]
assert actual and actual[0] == expected_header, f"TSV header is incorrect. Expected {expected_header}, got {actual[0] if actual else None}"
assert len(actual) >= 2, "TSV file should contain at least a header and one data row."
assert actual[1:] == expected_wide_rows(), f"TSV does not match the normalized, deduplicated, reshaped, and sorted raw CSV: {actual[1:]}"
for row in actual[1:]:
    assert len(row) == 6
    assert all(value == unicodedata.normalize("NFC", value) for value in row[2:]), "Translation is not NFC-normalized"

# Preserve the original fixture-specific assertions.
fixture = next((row for row in actual[1:] if len(row) == 6 and row[1] == "EVT-001"), None)
assert fixture is not None, "The expected row for EVT-001 was not found in the TSV."
assert fixture[0] == "2023-10-01T10:00:00Z"
assert fixture[2] == "Hello"
assert fixture[3] == "Hola"
assert fixture[4] == "Bonjour"
assert fixture[5] == "MISSING"

# Preserve the original live-server checks.
status, text = request("EVT-001", "es", AUTH)
assert status == 200, f"Expected status code 200, got {status}. Response: {text}"
assert "Event EVT-001 occurred at" in text
assert "Translation: Hola" in text
assert "ago" in text
status, _ = request("EVT-001", "es")
assert status in (401, 403), f"Expected 401 or 403 without authorization, got {status}"
status, _ = request("EVT-001", "zh", AUTH)
assert status == 404, f"Expected 404 for missing translation, got {status}"
status, _ = request("EVT-999", "en", AUTH)
assert status == 404, f"Expected 404 for missing event, got {status}"

# Compile the submitted server and verify that its build really depends on both required packages.
main_go = os.path.join(SERVER_DIR, "main.go")
assert os.path.isfile(main_go), f"File missing: {main_go}"
with open(main_go, encoding="utf-8") as handle:
    server_source = handle.read()
assert "text/template" in server_source, "Server does not import text/template"
assert re.search(r"\btemplate\s*\.", server_source), "Server does not use text/template"
env = dict(os.environ, GOPROXY="off", GOWORK="off")
deps = subprocess.run(
    ["go", "list", "-deps", "."], cwd=SERVER_DIR, env=env, check=True,
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30,
).stdout.splitlines()
assert "github.com/dustin/go-humanize" in deps, "Server does not depend on the fixed go-humanize module"
assert "text/template" in deps, "Server build does not depend on text/template"
server_bin = "/tmp/submitted-loc-server"
subprocess.run(
    ["go", "build", "-o", server_bin, "."], cwd=SERVER_DIR, env=env, check=True,
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30,
)

# Replace the TSV with unpredictable records and execute the submitted binary.
# This defeats servers that hardcode the public fixture or canned responses.
with open(TSV, "rb") as handle:
    original_tsv = handle.read()
unique = uuid.uuid4().hex
random_event = "EVT-" + unique[:12]
other_event = "EVT-" + unique[12:24]
translations = {
    "en": "English-" + unique,
    "es": unicodedata.normalize("NFC", "Cafe\u0301-" + unique),
    "fr": "Francais-" + unique,
}
try:
    with open(TSV, "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, delimiter="\t", lineterminator="\n")
        writer.writerow(expected_header)
        writer.writerow(["2020-02-03T04:05:06Z", random_event, translations["en"], translations["es"], translations["fr"], "MISSING"])
        writer.writerow(["2021-06-07T08:09:10Z", other_event, "Other-" + unique, "MISSING", "MISSING", "MISSING"])

    stop_port(8080)
    process = subprocess.Popen(
        [server_bin], cwd=SERVER_DIR, env=env,
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 8
    while time.time() < deadline:
        if process.poll() is not None:
            raise AssertionError(f"Compiled server exited early with status {process.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.2):
                break
        except OSError:
            time.sleep(0.1)
    else:
        raise AssertionError("Compiled server did not listen on 127.0.0.1:8080")

    for lang, translation in translations.items():
        status, body = request(random_event, lang, AUTH)
        assert status == 200, f"Dynamic {lang} request returned {status}: {body}"
        assert f"Event {random_event} occurred at 2020-02-03T04:05:06Z." in body
        assert f"Translation: {translation}." in body
        assert "ago" in body, f"Response lacks humanized time: {body}"

    status, _ = request(random_event, "zh", AUTH)
    assert status == 404, f"MISSING dynamic translation returned {status}"
    status, _ = request(random_event, "de", AUTH)
    assert status == 404, f"Unknown dynamic language returned {status}"
    status, _ = request("absent-" + unique, "en", AUTH)
    assert status == 404, f"Unknown dynamic event returned {status}"
    for bad_header in ({}, {"Authorization": "Bearer loc-eng-token "}, {"Authorization": "bearer loc-eng-token"}):
        status, _ = request(random_event, "en", bad_header)
        assert status in (401, 403), f"Non-exact authorization was accepted with status {status}"

    # The server was required to load the TSV into memory, not reread it per request.
    with open(TSV, "w", encoding="utf-8") as handle:
        handle.write("timestamp\tevent_id\ten\tes\tfr\tzh\n")
    status, body = request(random_event, "en", AUTH)
    assert status == 200 and translations["en"] in body, "Server did not retain the loaded TSV data in memory"
finally:
    with open(TSV, "wb") as handle:
        handle.write(original_tsv)
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
