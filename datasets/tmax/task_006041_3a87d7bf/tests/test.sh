#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import stat
import subprocess

SOURCE = "/home/user/etl_processor.c"
INPUT = "/home/user/input.csv"
OUTPUT = "/home/user/output.csv"
BINARY = "/tmp/etl_processor_submission"

ORIGINAL_INPUT = """ts,sensor_id,reading
10, reactor_temp ,200.0
10,reactor_temp,205.0
12,Reactor_Temp,210.0
15,reactor_temp,-50.0
18,reactor_temp,225.0
22,reactor_temp,235.0
30,reactor_temp,255.0
40,reactor_temp,400.0
50,other_sensor,410.0
50,reactor_temp,410.0
"""

EXPECTED_ORIGINAL = """ts,reading,is_anomaly
10,205.0,0
20,230.0,0
30,255.0,0
40,400.0,1
50,410.0,0"""


def compile_submission():
    assert os.path.isfile(SOURCE), f"Expected C source file {SOURCE} does not exist."
    mode = os.stat(SOURCE).st_mode
    assert stat.S_ISREG(mode), f"{SOURCE} must be a regular file."
    assert os.path.getsize(SOURCE) > 0, f"{SOURCE} is empty."

    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE, "-o", BINARY, "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Failed to compile {SOURCE}.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)


def run_program(csv_text):
    with open(INPUT, "w") as f:
        f.write(csv_text)
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    result = subprocess.run(
        [BINARY],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Program exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"Expected output file {OUTPUT} does not exist."
    with open(OUTPUT, "r") as f:
        return f.read().strip()


def reference_output(rows):
    cleaned = {}
    for ts_text, sensor, reading_text in rows:
        if sensor.strip().lower() != "reactor_temp":
            continue
        ts = int(ts_text)
        reading = float(reading_text)
        if reading < 0.0 or reading > 5000.0:
            continue
        if ts not in cleaned or reading > cleaned[ts]:
            cleaned[ts] = reading

    assert cleaned
    times = sorted(cleaned)
    assert (times[-1] - times[0]) % 10 == 0
    targets = list(range(times[0], times[-1] + 1, 10))
    values = []
    for target in targets:
        if target in cleaned:
            value = cleaned[target]
        else:
            before = max(t for t in times if t < target)
            after = min(t for t in times if t > target)
            fraction = (target - before) / (after - before)
            value = cleaned[before] + fraction * (cleaned[after] - cleaned[before])
        values.append(value)

    lines = ["ts,reading,is_anomaly"]
    for i, (target, value) in enumerate(zip(targets, values)):
        anomaly = 0 if i == 0 else int(abs(value - values[i - 1]) > 100.0)
        lines.append(f"{target},{value:.1f},{anomaly}")
    return "\n".join(lines)


def rows_to_csv(rows):
    return "ts,sensor_id,reading\n" + "\n".join(
        f"{ts},{sensor},{reading}" for ts, sensor, reading in rows
    ) + "\n"


def test_final_state():
    compile_submission()

    # Preserve the original verifier's fixed-fixture assertions, but obtain the
    # output by compiling and executing the submitted program.
    content = run_program(ORIGINAL_INPUT)
    output_csv_path = OUTPUT
    assert os.path.isfile(output_csv_path), f"Expected output file {output_csv_path} does not exist."
    assert content == EXPECTED_ORIGINAL, (
        f"Content of {output_csv_path} does not match expected.\n"
        f"Expected:\n{EXPECTED_ORIGINAL}\n\nActual:\n{content}"
    )

    rng = random.SystemRandom()
    base1 = 1000 + secrets.randbelow(5000) * 10
    v1 = 100 + secrets.randbelow(200)
    rows1 = [
        (str(base1), " reactor_temp ", str(v1)),
        (str(base1), "REACTOR_TEMP", str(v1 + 5)),
        (str(base1 + 4), "Reactor_Temp", str(v1 + 20)),
        (str(base1 + 10), "other_sensor", "4999"),
        (str(base1 + 14), "reactor_temp ", str(v1 + 220)),
        (str(base1 + 20), "reactor_temp", "-1"),
        (str(base1 + 20), " reactor_temp", "5001"),
        (str(base1 + 24), "reactor_temp", str(v1 + 240)),
        (str(base1 + 30), "reactor_temp", str(v1 + 50)),
        (str(base1 + 40), "reactor_temp", str(v1 + 60)),
    ]
    rng.shuffle(rows1)

    base2 = 70000 + secrets.randbelow(3000) * 10
    v2 = 300 + secrets.randbelow(300)
    rows2 = [
        (str(base2), "\tREACTOR_TEMP\t", str(v2)),
        (str(base2 + 5), "reactor_temp", str(v2 + 30)),
        (str(base2 + 15), " Reactor_Temp ", str(v2 + 60)),
        (str(base2 + 15), "reactor_temp", str(v2 + 70)),
        (str(base2 + 25), "REACTOR_TEMP", str(v2 + 300)),
        (str(base2 + 30), "reactor_temp_backup", str(v2 + 1000)),
        (str(base2 + 35), " reactor_temp", str(v2 + 290)),
        (str(base2 + 40), "reactor_temp ", str(v2 + 295)),
        (str(base2 + 10), "reactor_temp", "-0.1"),
        (str(base2 + 20), "reactor_temp", "5000.1"),
    ]
    rng.shuffle(rows2)

    for rows in (rows1, rows2):
        expected = reference_output(rows)
        actual = run_program(rows_to_csv(rows))
        assert actual == expected, (
            "Program failed a generated ETL fixture.\n"
            f"Expected:\n{expected}\n\nActual:\n{actual}"
        )

    # Leave the requested output.csv corresponding to the supplied input fixture.
    final_content = run_program(ORIGINAL_INPUT)
    assert final_content == EXPECTED_ORIGINAL
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
