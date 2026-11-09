#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import resource
import secrets
import subprocess

import pytest

PROJECT = "/home/user/config_tracker"
MANIFEST = os.path.join(PROJECT, "Cargo.toml")
MAIN_RS = os.path.join(PROJECT, "src/main.rs")
INPUT = "/home/user/config_events.tsv"
OUTPUT = "/home/user/latest_state.csv"
EXECUTABLE = None


def write_events(events):
    with open(INPUT, "wb") as f:
        for ts, server, key, value in events:
            f.write(str(ts).encode("ascii"))
            f.write(b"\t")
            f.write(server.encode("utf-8"))
            f.write(b"\t")
            f.write(key.encode("utf-8"))
            f.write(b"\t")
            f.write(value)
            f.write(b"\n")


def build_program():
    result = subprocess.run(
        ["cargo", "build", "--manifest-path", MANIFEST, "--message-format=json"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, f"Cargo build failed:\n{result.stderr}"

    executables = []
    for line in result.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        executable = message.get("executable")
        target = message.get("target", {})
        if executable and os.path.realpath(target.get("src_path", "")) == os.path.realpath(MAIN_RS):
            executables.append(executable)

    assert executables, "Cargo did not build src/main.rs as an executable binary."
    executable = executables[-1]
    assert os.path.isfile(executable), f"Built executable is missing: {executable}"
    assert os.access(executable, os.X_OK), f"Built artifact is not executable: {executable}"
    return executable


def run_program(memory_limit=None, timeout=120):
    if os.path.lexists(OUTPUT):
        if os.path.isdir(OUTPUT) and not os.path.islink(OUTPUT):
            raise AssertionError(f"{OUTPUT} is unexpectedly a directory")
        os.unlink(OUTPUT)

    preexec_fn = None
    if memory_limit is not None:
        def apply_limit():
            resource.setrlimit(resource.RLIMIT_AS, (memory_limit, memory_limit))
        preexec_fn = apply_limit

    result = subprocess.run(
        [EXECUTABLE],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        preexec_fn=preexec_fn,
    )
    assert result.returncode == 0, (
        f"The compiled Rust program exited with status {result.returncode}.\n"
        f"stdout: {result.stdout.decode('utf-8', errors='replace')}\n"
        f"stderr: {result.stderr.decode('utf-8', errors='replace')}"
    )
    assert os.path.isfile(OUTPUT), "Running the compiled program did not create latest_state.csv."


def read_output():
    try:
        with open(OUTPUT, "r", encoding="utf-8", newline="") as f:
            return list(csv.reader(f))
    except UnicodeDecodeError:
        pytest.fail("The output CSV is not valid UTF-8.")


def expected_rows(events):
    latest = {}
    for position, (timestamp, server, key, value) in enumerate(events):
        previous = latest.get(key)
        if previous is None or timestamp > previous[0] or (timestamp == previous[0] and position > previous[1]):
            latest[key] = (timestamp, position, server, value.decode("cp1252"))
    return [[key, latest[key][2], latest[key][3]] for key in sorted(latest)]


def test_rust_project_exists():
    """Verify that the Rust Cargo project was created in the correct location."""
    cargo_toml = "/home/user/config_tracker/Cargo.toml"
    main_rs = "/home/user/config_tracker/src/main.rs"

    assert os.path.exists(cargo_toml), f"Cargo.toml not found at {cargo_toml}. Did you create the Cargo project?"
    assert os.path.exists(main_rs), f"main.rs not found at {main_rs}. Did you create the Cargo project?"


def test_compiled_program_on_generated_inputs():
    global EXECUTABLE
    EXECUTABLE = build_program()

    token = secrets.token_hex(12)
    generated_events = [
        (10, "srv-old", f"zeta_{token}", b"obsolete"),
        (20, "srv-east", f"zeta_{token}", b"Price \x80, \x93" + token.encode("ascii") + b"\x94"),
        (30, "srv-first", f"alpha_{token}", b"first"),
        (30, 'srv,"tie"', f"alpha_{token}", b"later \x85 " + token.encode("ascii")),
        (5, "srv-middle", f"middle_{token}", b'path "quoted",' + token.encode("ascii")),
        (4, "srv-stale", f"middle_{token}", b"stale"),
    ]
    write_events(generated_events)
    run_program()
    assert read_output() == [
        ["config_key", "server_name", "decoded_value"],
        *expected_rows(generated_events),
    ], "The compiled program failed generated CP1252, timestamp, tie-breaking, sorting, or CSV-escaping cases."

    # A file larger than the process address-space limit distinguishes streaming
    # processing from implementations that read the entire input into memory.
    large_value = b"A" * (1024 * 1024)
    with open(INPUT, "wb") as f:
        for i in range(120):
            f.write(b"100\tbulk-server\tbulk_key\t")
            f.write(large_value)
            f.write(str(i).encode("ascii"))
            f.write(b"\n")
        f.write(b"100\tfinal-server\tbulk_key\tstreamed-final\n")

    run_program(memory_limit=96 * 1024 * 1024, timeout=180)
    assert read_output() == [
        ["config_key", "server_name", "decoded_value"],
        ["bulk_key", "final-server", "streamed-final"],
    ], "The program did not correctly process a file larger than its memory limit in streaming fashion."

    # Re-run against the original fixture so the original content assertions
    # remain in force and the requested final artifact is left ready to inspect.
    original_events = [
        (1630000000, "srv-alpha", "db_timeout", b"30s"),
        (1630000005, "srv-beta", "db_timeout", b"45s"),
        (1630000010, "srv-alpha", "welcome_msg", b"Hello \x93World\x94"),
        (1630000015, "srv-gamma", "welcome_msg", b"Maintenance \x85"),
        (1630000002, "srv-beta", "timezone", b"Europe/Paris"),
        (1630000020, "srv-alpha", "db_timeout", b"60s"),
        (1630000001, "srv-delta", "system_path", b"C:\\Windows\\System32"),
    ]
    write_events(original_events)
    run_program()


def test_latest_state_csv_exists():
    """Verify that the output CSV file was created."""
    output_csv = "/home/user/latest_state.csv"
    assert os.path.exists(output_csv), f"Output file {output_csv} is missing."
    assert os.path.isfile(output_csv), f"Path {output_csv} is not a regular file."


def test_latest_state_csv_content():
    """Verify that the output CSV contains the correct aggregated state, headers, and sorting."""
    output_csv = "/home/user/latest_state.csv"

    try:
        with open(output_csv, "r", encoding="utf-8") as f:
            reader = csv.reader(f)
            rows = list(reader)
    except UnicodeDecodeError:
        pytest.fail("The output CSV is not valid UTF-8.")

    assert len(rows) > 0, "The output CSV is empty."

    expected_header = ["config_key", "server_name", "decoded_value"]
    assert rows[0] == expected_header, f"Expected header {expected_header}, but got {rows[0]}"

    expected_data = [
        ["db_timeout", "srv-alpha", "60s"],
        ["system_path", "srv-delta", "C:\\Windows\\System32"],
        ["timezone", "srv-beta", "Europe/Paris"],
        ["welcome_msg", "srv-gamma", "Maintenance …"],
    ]

    actual_data = rows[1:]
    assert actual_data == expected_data, (
        f"The data rows in the CSV do not match the expected output. "
        f"Expected:\n{expected_data}\nGot:\n{actual_data}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
