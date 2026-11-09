#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import secrets
import stat
import subprocess


def compute_expected_changes(input_csv_path):
    """Derive the expected output from the current input file."""
    with open(input_csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            return ""

        config_keys = headers[2:]
        last_state = {}
        changes = {}

        for row in reader:
            if not row or len(row) < 2:
                continue
            server_id = row[1].upper()
            if server_id not in last_state:
                last_state[server_id] = {}
                changes[server_id] = {k: 0 for k in config_keys}

            for i, key in enumerate(config_keys):
                if 2 + i < len(row):
                    val = row[2 + i]
                    if key in last_state[server_id] and last_state[server_id][key] != val:
                        changes[server_id][key] += 1
                    last_state[server_id][key] = val

        result = []
        for server_id in sorted(changes):
            for key in sorted(config_keys):
                result.append(f"{server_id},{key},{changes[server_id][key]}")
        return "\n".join(result) + ("\n" if result else "")


def test_tracker_c_exists():
    file_path = "/home/user/tracker.c"
    assert os.path.isfile(file_path), f"Source file {file_path} is missing."


def test_tracker_executable_exists():
    file_path = "/home/user/tracker"
    assert os.path.isfile(file_path), f"Executable {file_path} is missing."
    st = os.stat(file_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{file_path} is not executable."
    with open(file_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{file_path} is not a compiled native executable."


def test_changes_csv_matches_expected():
    input_path = "/home/user/configs.csv"
    output_path = "/home/user/changes.csv"

    assert os.path.isfile(input_path), f"Input file {input_path} is missing."
    assert os.path.isfile(output_path), f"Output file {output_path} is missing."

    expected_csv_content = compute_expected_changes(input_path)
    with open(output_path, "r") as f:
        actual_content = f.read()

    expected_lines = [line for line in expected_csv_content.strip().split("\n") if line]
    actual_lines = [line for line in actual_content.strip().split("\n") if line]
    assert actual_lines == expected_lines, (
        f"Output in {output_path} does not match expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def write_case(headers, rows):
    with open("/home/user/configs.csv", "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(headers)
        writer.writerows(rows)


def make_random_case(rng):
    key_count = rng.randint(3, 8)
    server_count = rng.randint(2, 5)
    round_count = rng.randint(4, 7)

    keys = [f"{chr(90-i)}Key_{secrets.token_hex(2)}" for i in range(key_count)]
    servers = [f"node-{i}-{secrets.token_hex(2)}" for i in range(server_count)]
    states = {
        server: [f"v_{secrets.token_hex(3)}" for _ in keys]
        for server in servers
    }

    rows = []
    start = rng.randint(10000, 90000)
    for round_index in range(round_count):
        order = list(servers)
        rng.shuffle(order)
        for server in order:
            if round_index:
                for i in range(key_count):
                    if rng.random() < 0.45:
                        states[server][i] = f"v_{secrets.token_hex(3)}"
            rendered_server = server.upper() if rng.random() < 0.35 else server
            rows.append([start + round_index * 17, rendered_server] + list(states[server]))
    return ["timestamp", "server_id"] + keys, rows


def run_and_check(binary, headers, rows):
    write_case(headers, rows)
    expected = compute_expected_changes("/home/user/configs.csv")
    if os.path.exists("/home/user/changes.csv"):
        os.remove("/home/user/changes.csv")

    result = subprocess.run(
        [binary],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=8,
    )
    assert result.returncode == 0, (
        f"{binary} exited with {result.returncode}. stderr: {result.stderr}"
    )
    assert os.path.isfile("/home/user/changes.csv"), (
        f"{binary} did not create /home/user/changes.csv"
    )
    with open("/home/user/changes.csv", "r") as f:
        actual = f.read()
    assert actual == expected, (
        f"{binary} produced incorrect output for a verifier-generated input.\n"
        f"Expected:\n{expected}\nActual:\n{actual}"
    )


def test_source_compiles_and_both_artifacts_handle_generated_inputs():
    input_path = "/home/user/configs.csv"
    output_path = "/home/user/changes.csv"
    with open(input_path, "rb") as f:
        original_input = f.read()
    original_output = None
    if os.path.exists(output_path):
        with open(output_path, "rb") as f:
            original_output = f.read()

    compiled = "/tmp/tracker_from_source"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "/home/user/tracker.c", "-o", compiled],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert compile_result.returncode == 0, (
        "tracker.c did not compile successfully:\n" + compile_result.stderr
    )

    deterministic_headers = [
        "timestamp", "server_id", "ZuluMode", "AlphaLimit", "MiddleFlag"
    ]
    deterministic_rows = [
        [10, "edge-b", "on", "10", "red"],
        [10, "edge-a", "off", "20", "blue"],
        [20, "EDGE-A", "on", "20", "blue"],
        [20, "edge-b", "on", "11", "green"],
        [30, "edge-b", "off", "11", "green"],
        [30, "Edge-A", "on", "25", "red"],
        [40, "edge-a", "off", "25", "red"],
        [40, "EDGE-B", "off", "12", "blue"],
    ]

    seed = int.from_bytes(secrets.token_bytes(16), "big")
    rng = random.Random(seed)
    cases = [(deterministic_headers, deterministic_rows)]
    cases.extend(make_random_case(rng) for _ in range(3))

    try:
        for binary in (compiled, "/home/user/tracker"):
            for headers, rows in cases:
                run_and_check(binary, headers, rows)
    finally:
        with open(input_path, "wb") as f:
            f.write(original_input)
        if original_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
