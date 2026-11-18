#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import random
import re
import subprocess
from collections import defaultdict
from pathlib import Path

INPUT_FILE = "/home/user/config_events.jsonl"
OUTPUT_FILE = "/home/user/invalid_changes.csv"
PROJECT_DIR = "/home/user/config_tracker"


def expected_rows_from_events(events):
    events_by_service = defaultdict(list)
    for event in events:
        events_by_service[event["service"]].append(event)

    expected_violations = []
    for service, service_events in events_by_service.items():
        service_events.sort(key=lambda x: x["timestamp"])
        for i in range(1, len(service_events)):
            if service_events[i]["timestamp"] - service_events[i - 1]["timestamp"] < 1000:
                expected_violations.append(service_events[i])

    expected_violations.sort(key=lambda x: (x["service"], x["timestamp"]))
    return [[v["service"], str(v["timestamp"]), v["change_id"]] for v in expected_violations]


def read_actual_csv(output_file):
    actual_rows = []
    with open(output_file, "r", encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            header = []
        assert header == ["service", "timestamp", "change_id"], f"CSV header is incorrect: {header}"
        for row in reader:
            if row:
                actual_rows.append(row)
    return actual_rows


def test_invalid_changes_csv():
    input_file = "/home/user/config_events.jsonl"
    output_file = "/home/user/invalid_changes.csv"

    assert os.path.exists(input_file), f"Input file {input_file} is missing."
    assert os.path.exists(output_file), f"Output file {output_file} is missing."

    # Read and parse input events
    events_by_service = defaultdict(list)
    with open(input_file, "r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            event = json.loads(line)
            events_by_service[event["service"]].append(event)

    # Compute expected violations
    expected_violations = []
    for service, events in events_by_service.items():
        events.sort(key=lambda x: x["timestamp"])
        for i in range(1, len(events)):
            if events[i]["timestamp"] - events[i-1]["timestamp"] < 1000:
                expected_violations.append(events[i])

    # Sort violations as required: primarily by service (ascending), secondarily by timestamp (ascending)
    expected_violations.sort(key=lambda x: (x["service"], x["timestamp"]))

    # Read actual CSV
    actual_rows = []
    with open(output_file, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            header = []
        assert header == ["service", "timestamp", "change_id"], f"CSV header is incorrect: {header}"

        for row in reader:
            if row:
                actual_rows.append(row)

    # Format expected rows
    expected_rows = [
        [v["service"], str(v["timestamp"]), v["change_id"]]
        for v in expected_violations
    ]

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} violation rows, but found {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch: expected {expected}, got {actual}."


def test_rust_project_exists():
    project_dir = "/home/user/config_tracker"
    assert os.path.isdir(project_dir), f"Rust project directory {project_dir} is missing."
    assert os.path.isfile(os.path.join(project_dir, "Cargo.toml")), "Cargo.toml is missing in the Rust project."


def test_rust_source_uses_streaming_input():
    src_dir = Path(PROJECT_DIR) / "src"
    rust_files = list(src_dir.rglob("*.rs")) if src_dir.is_dir() else []
    assert rust_files, "The Rust project has no Rust source files under src/."

    source = "\n".join(path.read_text(encoding="utf-8") for path in rust_files)
    compact = re.sub(r"\s+", "", source).lower()

    forbidden = [
        "read_to_string(",
        "read_to_end(",
        "include_str!(\"/home/user/config_events.jsonl\")",
        "include_bytes!(\"/home/user/config_events.jsonl\")",
    ]
    for pattern in forbidden:
        assert pattern not in compact, f"Input is not streamed: found whole-file operation {pattern}."
    assert not re.search(r"(?:std::)?fs::read\(", compact), "Input is not streamed: std::fs::read/fs::read loads the whole file."

    buffered_line_stream = "bufreader" in compact and any(
        marker in compact for marker in (".lines(", "read_line(", "read_until(", ".split(")
    )
    serde_stream = "serde_json" in compact and "from_reader(" in compact and (
        "into_iter" in compact or "streamdeserializer" in compact
    )
    assert buffered_line_stream or serde_stream, "Rust source does not show buffered/streaming JSONL input processing."


def test_compiled_rust_program_handles_fresh_input():
    original_input = Path(INPUT_FILE).read_bytes()
    output_path = Path(OUTPUT_FILE)
    output_existed = output_path.exists()
    original_output = output_path.read_bytes() if output_existed else b""

    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    services = ["Auth-Fresh", "équipe-service", "Ω-config", "設定サービス", "🚀-control"]
    events = []
    for service_index, service in enumerate(services):
        timestamp = 1800000000000 + service_index * 10000000 + rng.randrange(1000, 9000)
        for event_index in range(40):
            if event_index:
                timestamp += rng.choice([137, 499, 999, 1000, 1001, 1733])
            events.append({
                "timestamp": timestamp,
                "service": service,
                "change_id": f"fresh-{service_index}-{event_index}-{rng.randrange(10**9)}",
                "payload_size": rng.randrange(1, 65536),
            })
    rng.shuffle(events)
    expected_rows = expected_rows_from_events(events)

    try:
        with open(INPUT_FILE, "w", encoding="utf-8") as f:
            for event in events:
                f.write(json.dumps(event, ensure_ascii=False) + "\n")
        if output_path.exists():
            output_path.unlink()

        env = os.environ.copy()
        env["RUSTUP_HOME"] = "/opt/rust"
        env["CARGO_HOME"] = "/opt/cargo"
        env["PATH"] = "/opt/cargo/bin:" + env.get("PATH", "")
        result = subprocess.run(
            ["/opt/cargo/bin/cargo", "run", "--quiet", "--manifest-path", os.path.join(PROJECT_DIR, "Cargo.toml")],
            cwd=PROJECT_DIR,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=180,
        )
        assert result.returncode == 0, f"Rust program failed to compile or run:\n{result.stderr}"
        assert output_path.is_file(), "Running the Rust program did not create /home/user/invalid_changes.csv."
        actual_rows = read_actual_csv(OUTPUT_FILE)
        assert actual_rows == expected_rows, f"Rust program produced incorrect results on fresh input. Expected {expected_rows}, got {actual_rows}."
    finally:
        Path(INPUT_FILE).write_bytes(original_input)
        if output_existed:
            output_path.write_bytes(original_output)
        elif output_path.exists():
            output_path.unlink()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
