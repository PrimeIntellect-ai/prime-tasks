#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import signal
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PIPELINE = "/home/user/loc_pipeline/pipeline.py"
JSONL_OUT = "/home/user/loc_pipeline/clean_translations.jsonl"
CSV_OUT = "/home/user/loc_pipeline/rolling_stats.csv"

ORIGINAL_RAW = r'''{"id": "btn_ok", "lang": "en", "text": "OK", "timestamp": 100}
{"id": "btn_ok", "lang": "en", "text": "Okay", "timestamp": 105}
{"id": "btn_cancel", "lang": "en", "text": "Cancel", "timestamp": 110}
{"id": "msg_error", "lang": "en", "text": "Error \u00xx", "timestamp": 120}
{"id": "btn_ok", "lang": "fr", "text": "D\u00e9ccord", "timestamp": 130}
{"id": "msg_error", "lang": "fr", "text": "Erreur", "timestamp": 140}
{"id": "lbl_save", "lang": "ENG", "text": "Save", "timestamp": 150}
{"id": "lbl_save", "lang": "en", "text": "Save", "timestamp": 160}
{"id": "msg_warn", "lang": "fr", "text": "Attention\uZZZZ", "timestamp": 170}
{"id": "btn_ok", "lang": "fr", "text": "D\u00e9ccord!", "timestamp": 180}
{"id": "msg_info", "lang": "fr", "text": "Info", "timestamp": 190}
{"id": "msg_success", "lang": "fr", "text": "Succ\u00e8s", "timestamp": 200}
'''.encode("utf-8")

class FixtureHandler(BaseHTTPRequestHandler):
    payload = b""
    requests = 0

    def do_GET(self):
        if self.path != "/raw_translations.jsonl":
            self.send_error(404)
            return
        type(self).requests += 1
        body = type(self).payload
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def kill_existing_port_8000_listener():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r", encoding="ascii") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[3] == "0A":
                        port = int(fields[1].rsplit(":", 1)[1], 16)
                        if port == 8000:
                            inodes.add(fields[9])
        except FileNotFoundError:
            pass
    if not inodes:
        return
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if any(target == f"socket:[{inode}]" for inode in inodes):
                    os.kill(int(pid), signal.SIGTERM)
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    time.sleep(0.4)


def run_pipeline(payload):
    FixtureHandler.payload = payload
    FixtureHandler.requests = 0
    for path in (JSONL_OUT, CSV_OUT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    result = subprocess.run(
        [sys.executable, PIPELINE],
        cwd="/home/user/loc_pipeline",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"pipeline.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert FixtureHandler.requests > 0, "pipeline.py did not fetch /raw_translations.jsonl over HTTP"


def read_jsonl():
    records = []
    with open(JSONL_OUT, "r", encoding="utf-8") as f:
        for line in f:
            records.append(json.loads(line))
    return records


def read_csv():
    with open(CSV_OUT, "r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        rows = list(reader)
    return header, rows


def assert_original_fixture():
    assert os.path.isfile(JSONL_OUT), f"Output file {JSONL_OUT} is missing."
    assert os.path.isfile(CSV_OUT), f"Output file {CSV_OUT} is missing."

    records = read_jsonl()
    expected_ids = ["btn_ok", "btn_cancel", "msg_error", "msg_error", "lbl_save", "msg_warn", "btn_ok", "msg_info", "msg_success"]
    expected_langs = ["en", "en", "en", "fr", "en", "fr", "fr", "fr", "fr"]
    expected_timestamps = [105, 110, 120, 140, 160, 170, 180, 190, 200]
    expected_texts = ["Okay", "Cancel", "Error �", "Erreur", "Save", "Attention�", "Déccord!", "Info", "Succès"]
    assert len(records) == 9, f"Expected 9 records in clean_translations.jsonl, found {len(records)}"
    for i, record in enumerate(records):
        assert record["id"] == expected_ids[i], f"Record {i} id mismatch: expected {expected_ids[i]}, got {record['id']}"
        assert record["lang"] == expected_langs[i], f"Record {i} lang mismatch: expected {expected_langs[i]}, got {record['lang']}"
        assert record["timestamp"] == expected_timestamps[i], f"Record {i} timestamp mismatch: expected {expected_timestamps[i]}, got {record['timestamp']}"
        assert record["text"] == expected_texts[i], f"Record {i} text mismatch: expected {expected_texts[i]}, got {record['text']}"

    header, rows = read_csv()
    expected_header = ["timestamp", "lang", "id", "text_length", "rolling_avg_len"]
    assert header == expected_header, f"CSV header mismatch: expected {expected_header}, got {header}"
    expected_rows = [
        ["105", "en", "btn_ok", "4", "4.00"],
        ["110", "en", "btn_cancel", "6", "5.00"],
        ["120", "en", "msg_error", "7", "5.67"],
        ["140", "fr", "msg_error", "6", "6.00"],
        ["160", "en", "lbl_save", "4", "5.67"],
        ["170", "fr", "msg_warn", "10", "8.00"],
        ["180", "fr", "btn_ok", "8", "8.00"],
        ["190", "fr", "msg_info", "4", "7.33"],
        ["200", "fr", "msg_success", "6", "6.00"],
    ]
    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in CSV, found {len(rows)}"
    for i, (row, expected) in enumerate(zip(rows, expected_rows)):
        assert row[0] == expected[0], f"Row {i} timestamp mismatch"
        assert row[1] == expected[1], f"Row {i} lang mismatch"
        assert row[2] == expected[2], f"Row {i} id mismatch"
        assert row[3] == expected[3], f"Row {i} text_length mismatch"
        assert float(row[4]) == float(expected[4]), f"Row {i} rolling_avg_len mismatch: expected {expected[4]}, got {row[4]}"


def make_dynamic_fixture():
    rng = random.SystemRandom()
    token = "%08x" % rng.randrange(2**32)
    base = rng.randrange(1000, 50000)
    parsed = [
        {"id": "a_" + token, "lang": "en", "text": "old", "timestamp": base + 40},
        {"id": "a_" + token, "lang": "en", "text": "new-" + token[:3], "timestamp": base + 90},
        {"id": "bad_" + token, "lang": "en", "text": "broken � tail", "timestamp": base + 100},
        {"id": "e3_" + token, "lang": "en", "text": "eleven chars", "timestamp": base + 160},
        {"id": "e4_" + token, "lang": "en", "text": "z", "timestamp": base + 220},
        {"id": "fx_" + token, "lang": "fr", "text": "ancien", "timestamp": base + 80},
        {"id": "fx_" + token, "lang": "fr", "text": "nouveau", "timestamp": base + 180},
        {"id": "fy_" + token, "lang": "fr", "text": "été", "timestamp": base + 120},
        {"id": "fz_" + token, "lang": "fr", "text": "bonjour!", "timestamp": base + 200},
        {"id": "fb_" + token, "lang": "fr", "text": "fin �", "timestamp": base + 240},
        {"id": "d1_" + token, "lang": "de", "text": "grüß", "timestamp": base + 110},
        {"id": "d2_" + token, "lang": "de", "text": "längeres", "timestamp": base + 210},
        {"id": "drop1_" + token, "lang": "EN", "text": "drop", "timestamp": base + 130},
        {"id": "drop2_" + token, "lang": "eng", "text": "drop", "timestamp": base + 140},
    ]
    wire = []
    for record in parsed:
        raw_record = dict(record)
        if record["id"].startswith("bad_"):
            raw_record["text"] = "broken __BAD__ tail"
            line = json.dumps(raw_record, ensure_ascii=True).replace("__BAD__", r"\u0Xq!")
        elif record["id"].startswith("fb_"):
            raw_record["text"] = "fin __BAD__"
            line = json.dumps(raw_record, ensure_ascii=True).replace("__BAD__", r"\uZZ9?")
        else:
            line = json.dumps(raw_record, ensure_ascii=True)
        wire.append(line)
    rng.shuffle(wire)
    return ("\n".join(wire) + "\n").encode("utf-8"), parsed


def expected_from_parsed(parsed):
    valid = [r for r in parsed if len(r["lang"]) == 2 and r["lang"].islower() and r["lang"].isalpha() and r["lang"].isascii()]
    newest = {}
    for record in valid:
        key = (record["id"], record["lang"])
        if key not in newest or record["timestamp"] > newest[key]["timestamp"]:
            newest[key] = record
    records = sorted(newest.values(), key=lambda r: r["timestamp"])
    history = {}
    rows = []
    for record in records:
        length = len(record["text"])
        values = history.setdefault(record["lang"], [])
        values.append(length)
        window = values[-3:]
        rows.append([
            str(record["timestamp"]), record["lang"], record["id"], str(length),
            f"{sum(window) / len(window):.2f}",
        ])
    return records, rows


def assert_dynamic_fixture(parsed):
    assert os.path.isfile(JSONL_OUT), f"Output file {JSONL_OUT} is missing."
    assert os.path.isfile(CSV_OUT), f"Output file {CSV_OUT} is missing."
    expected_records, expected_rows = expected_from_parsed(parsed)
    records = read_jsonl()
    assert records == expected_records, f"Dynamic JSONL output mismatch:\nexpected={expected_records!r}\nactual={records!r}"
    header, rows = read_csv()
    assert header == ["timestamp", "lang", "id", "text_length", "rolling_avg_len"]
    assert rows == expected_rows, f"Dynamic CSV output mismatch:\nexpected={expected_rows!r}\nactual={rows!r}"
    for row in rows:
        assert len(row[4].partition(".")[2]) == 2, f"rolling average is not formatted to exactly 2 decimals: {row[4]}"


def main():
    assert os.path.isfile(PIPELINE), f"Required pipeline script {PIPELINE} is missing."
    kill_existing_port_8000_listener()
    server = ThreadingHTTPServer(("127.0.0.1", 8000), FixtureHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        run_pipeline(ORIGINAL_RAW)
        assert_original_fixture()
        payload, parsed = make_dynamic_fixture()
        run_pipeline(payload)
        assert_dynamic_fixture(parsed)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


if __name__ == "__main__":
    main()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
