#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess

SOURCE = "/home/user/process.c"
BINARY = "/home/user/process"
OUTPUT = "/home/user/output.csv"
TELEMETRY = "/home/user/telemetry.jsonl"
METADATA = "/home/user/metadata.csv"

ORIGINAL_EXPECTED = [
    "ts,sensor_id,location,val",
    "1700000000,S1,North_Wing,12.5",
    "1700000010,S1,North_Wing,12.5",
    "1700000020,S1,North_Wing,15.0",
    "1700000030,S1,North_Wing,15.0",
    "1700000040,S1,North_Wing,14.5",
    "1700000050,S1,North_Wing,14.5",
    "1700000000,S2,South_Wing,0.0",
    "1700000010,S2,South_Wing,8.0",
    "1700000020,S2,South_Wing,8.5",
    "1700000030,S2,South_Wing,8.5",
    "1700000040,S2,South_Wing,8.5",
    "1700000050,S2,South_Wing,8.5",
]


def read_nonblank_lines(path):
    with open(path, "r", encoding="utf-8") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def assert_exact_output(expected):
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} is missing."
    assert os.path.isfile(OUTPUT), f"{OUTPUT} is not a file."
    actual = read_nonblank_lines(OUTPUT)
    assert len(actual) == len(expected), (
        f"Expected {len(expected)} lines in {OUTPUT}, but got {len(actual)}."
    )
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert got == want, (
            f"Mismatch at line {i + 1} in {OUTPUT}.\nExpected: {want}\nActual: {got}"
        )


def write_original_inputs():
    with open(METADATA, "w", encoding="utf-8", newline="") as f:
        f.write("sensor_id,location,group\n")
        f.write("S1,North_Wing,A\n")
        f.write("S2,South_Wing,B\n")

    lines = [
        r'{"ts": 1700000000, "sensor": "S1", "val": 12.5, "msg": "ok \u0041"}',
        r'{"ts": 1700000020, "sensor": "S1", "val": 15.0, "msg": "bad \uX9ZZ here"}',
        r'{"ts": 1700000040, "sensor": "S1", "val": 14.5, "msg": "end"}',
        r'{"ts": 1700000010, "sensor": "S2", "val": 8.0, "msg": "start"}',
        r'{"ts": 1700000020, "sensor": "S2", "val": 8.5, "msg": "mid \uG123"}',
    ]
    with open(TELEMETRY, "w", encoding="utf-8", newline="") as f:
        f.write("\n".join(lines) + "\n")


def run_program():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [BINARY], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), "The executed program did not create output.csv."


def make_msg_json(text, replacement=None):
    encoded = json.dumps(text)
    if replacement is not None:
        encoded = encoded.replace("TOKEN", replacement)
    return encoded


def make_record(ts, sensor, value, msg_json):
    return (
        f'{{"ts": {ts}, "sensor": {json.dumps(sensor)}, '
        f'"val": {value}, "msg": {msg_json}}}'
    )


def write_random_case(round_number):
    token = secrets.token_hex(4).upper()
    sensors = [f"D{token}", f"A{token}", f"Q{token}", f"M{token}"]
    locations = {
        sensor: f"Loc_{round_number}_{i}_{secrets.token_hex(2)}"
        for i, sensor in enumerate(sensors)
    }

    metadata_order = sensors[:]
    secrets.SystemRandom().shuffle(metadata_order)
    with open(METADATA, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["sensor_id", "location", "group"])
        for i, sensor in enumerate(metadata_order):
            writer.writerow([sensor, locations[sensor], f"G{i}"])

    def random_value():
        return (secrets.randbelow(180) + 21) / 10.0

    readings = {
        sensors[0]: {1700000000: random_value(), 1700000020: random_value(), 1700000040: random_value()},
        sensors[1]: {1700000010: random_value(), 1700000030: random_value()},
        sensors[2]: {1700000020: random_value(), 1700000050: random_value()},
        sensors[3]: {},
    }

    records = [
        make_record(1700000000, sensors[0], readings[sensors[0]][1700000000],
                    make_msg_json("bad TOKEN tail", "\\uX9ZZ")),
        make_record(1700000020, sensors[0], readings[sensors[0]][1700000020],
                    make_msg_json("valid TOKEN", "\\u0041")),
        make_record(1700000040, sensors[0], readings[sensors[0]][1700000040],
                    make_msg_json("plain message")),
        make_record(1700000010, sensors[1], readings[sensors[1]][1700000010],
                    make_msg_json("prefix TOKEN suffix", "\\uG123")),
        make_record(1700000030, sensors[1], readings[sensors[1]][1700000030],
                    make_msg_json("another message")),
        make_record(1700000020, sensors[2], readings[sensors[2]][1700000020],
                    make_msg_json("edge TOKEN", "\\u12G4")),
        make_record(1700000050, sensors[2], readings[sensors[2]][1700000050],
                    make_msg_json("done")),
        make_record(1700000010, f"UNKNOWN_{token}", random_value(),
                    make_msg_json("ignored TOKEN", "\\uZZZZ")),
    ]
    with open(TELEMETRY, "w", encoding="utf-8", newline="") as f:
        f.write("\n".join(records) + "\n")

    expected = ["ts,sensor_id,location,val"]
    for sensor in sorted(sensors):
        previous = 0.0
        for ts in range(1700000000, 1700000051, 10):
            if ts in readings[sensor]:
                previous = readings[sensor][ts]
            expected.append(f"{ts},{sensor},{locations[sensor]},{previous:.1f}")
    return expected


def test_process_c_exists():
    assert os.path.exists(SOURCE), f"Source file {SOURCE} is missing."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."


def test_output_csv_exists_and_correct():
    assert_exact_output(ORIGINAL_EXPECTED)


def test_compile_execute_and_generalize():
    if os.path.exists(BINARY):
        os.remove(BINARY)
    result = subprocess.run(
        ["gcc", SOURCE, "-o", BINARY, "-lm"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"gcc failed with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(BINARY), "gcc did not create /home/user/process."

    write_original_inputs()
    run_program()
    assert_exact_output(ORIGINAL_EXPECTED)

    for round_number in range(2):
        expected = write_random_case(round_number)
        run_program()
        assert_exact_output(expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
