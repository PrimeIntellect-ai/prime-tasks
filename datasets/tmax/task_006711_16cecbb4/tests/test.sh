#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess

SOURCE = "/home/user/process.cpp"
EXECUTABLE = "/home/user/process"
MEASUREMENTS = "/home/user/measurements.csv"
SENSORS = "/home/user/sensors.tsv"
OUTPUT = "/home/user/output.csv"


def run_process():
    result = subprocess.run(
        [EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Process exited with {result.returncode}. stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )


def write_original_fixture():
    with open(SENSORS, "w", newline="") as f:
        f.write("sensor_id\tstatus\n1\tactive\n2\tinactive\n3\tactive\n")

    with open(MEASUREMENTS, "w", newline="") as f:
        f.write('''timestamp,sensor_id,value,notes
1000,1,10.0,"Start"
1005,1,12.0,"Normal"
1010,1,14.0,"Note with
newline"
1015,2,99.0,"Ignore"
1020,3,5.0,"Okay"
1025,1,16.0,"End"
1030,3,10.0,"Another
newline
here"
1035,3,15.0,"Done"
1040,1,18.0,"Final"
''')


def test_cpp_source_exists():
    assert os.path.isfile(SOURCE), f"Expected C++ source file {SOURCE} does not exist."


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Expected executable file {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_output_csv_exists_and_correct():
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"process.cpp did not compile as C++17: {compile_result.stderr}"
    )
    assert os.path.isfile(EXECUTABLE), f"Expected executable file {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."

    write_original_fixture()
    run_process()

    assert os.path.isfile(OUTPUT), f"Expected output file {OUTPUT} does not exist."

    expected_output = """sensor_id,timestamp,rolling_avg
1,1000,10.00
1,1005,11.00
1,1010,12.00
1,1025,14.00
1,1040,16.00
3,1020,5.00
3,1030,7.50
3,1035,10.00"""

    with open(OUTPUT, "r") as f:
        actual_output = f.read().strip()

    expected_lines = expected_output.strip().splitlines()
    actual_lines = actual_output.strip().splitlines()

    assert len(actual_lines) == len(expected_lines), f"Output file has {len(actual_lines)} lines, expected {len(expected_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual}'."


def csv_quote(value):
    return '"' + value.replace('"', '""') + '"'


def expected_output(records, statuses):
    kept = [r for r in records if statuses.get(r[1]) == "active"]
    kept.sort(key=lambda r: (r[1], r[0]))
    windows = {}
    lines = ["sensor_id,timestamp,rolling_avg"]
    for timestamp, sensor_id, value, _notes in kept:
        window = windows.setdefault(sensor_id, [])
        window.append(value)
        if len(window) > 3:
            del window[0]
        average = sum(window) / len(window)
        lines.append(f"{sensor_id},{timestamp},{average:.2f}")
    return "\n".join(lines)


def write_generated_fixture(records, statuses, rng):
    metadata = list(statuses.items())
    rng.shuffle(metadata)
    with open(SENSORS, "w", newline="") as f:
        f.write("sensor_id\tstatus\n")
        for sensor_id, status in metadata:
            f.write(f"{sensor_id}\t{status}\n")

    shuffled = list(records)
    rng.shuffle(shuffled)
    with open(MEASUREMENTS, "w", newline="") as f:
        f.write("timestamp,sensor_id,value,notes\n")
        for timestamp, sensor_id, value, notes in shuffled:
            f.write(f"{timestamp},{sensor_id},{value:.1f},{csv_quote(notes)}\n")


def test_process_on_unpredictable_inputs():
    rng = random.Random(secrets.randbits(128))

    for case_number in range(3):
        sensor_ids = rng.sample(range(20, 900), 5)
        active_ids = sensor_ids[:3]
        inactive_ids = sensor_ids[3:]
        statuses = {sensor_id: "active" for sensor_id in active_ids}
        statuses.update({sensor_id: "inactive" for sensor_id in inactive_ids})

        records = []
        base = rng.randint(200000, 900000)
        for sensor_id in sensor_ids:
            count = 5 if sensor_id in active_ids else 3
            offsets = sorted(rng.sample(range(1, 500), count))
            for index, offset in enumerate(offsets):
                value = float(rng.randrange(-40, 102, 2))
                if index % 3 == 0:
                    notes = f"sensor {sensor_id}, case {case_number}\ncontinued note"
                elif index % 3 == 1:
                    notes = "first line\nsecond line\nthird line"
                else:
                    notes = "ordinary note"
                records.append((base + offset, sensor_id, value, notes))

        write_generated_fixture(records, statuses, rng)
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        run_process()

        assert os.path.isfile(OUTPUT), "Process did not generate /home/user/output.csv"
        with open(OUTPUT, "r") as f:
            actual = f.read().strip()
        expected = expected_output(records, statuses).strip()
        assert actual == expected, (
            f"Incorrect output for generated fixture {case_number}.\n"
            f"Expected:\n{expected}\nActual:\n{actual}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
