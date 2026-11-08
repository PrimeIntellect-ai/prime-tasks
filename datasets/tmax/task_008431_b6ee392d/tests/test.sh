#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess

PIPELINE = "/home/user/pipeline"
INPUT = f"{PIPELINE}/input"
OUTPUT = f"{PIPELINE}/output"
ARCHIVE = f"{PIPELINE}/archive"
BIN = f"{PIPELINE}/bin"
DETECTOR_SOURCE = f"{BIN}/detector.c"
DETECTOR_BIN = f"{BIN}/detector"
PROCESS_SCRIPT = f"{BIN}/process.sh"


def expected_lines(rows):
    mean_x = sum(row[1] for row in rows) / len(rows)
    mean_y = sum(row[2] for row in rows) / len(rows)
    anomalies = []
    for previous, current in zip(rows, rows[1:]):
        if math.hypot(current[1] - previous[1], current[2] - previous[2]) > 50.0:
            anomalies.append(str(current[0]))
    return [
        f"Mean X: {mean_x:.2f}",
        f"Mean Y: {mean_y:.2f}",
        f"Anomaly Count: {len(anomalies)}",
        f"Anomaly Timestamps: {','.join(anomalies) if anomalies else 'None'}",
    ]


def write_csv(path, rows):
    with open(path, "w") as f:
        for timestamp, sensor_x, sensor_y in rows:
            f.write(f"{timestamp},{sensor_x},{sensor_y}\n")


def assert_exact_output(path, rows):
    assert os.path.isfile(path), f"Output file missing: {path}"
    with open(path, "r") as f:
        actual = f.read().splitlines()
    expected = expected_lines(rows)
    assert actual == expected, f"Incorrect output for {path}. Expected {expected!r}, got {actual!r}"


def make_random_rows(count):
    timestamp = 300000 + secrets.randbelow(500000)
    rows = []
    for index in range(count):
        x = secrets.randbelow(801) - 400
        y = secrets.randbelow(801) - 400
        rows.append((timestamp + index * (1 + secrets.randbelow(9)), x, y))
    return rows


def test_directories_exist():
    dirs = [INPUT, OUTPUT, ARCHIVE, BIN]
    for directory in dirs:
        assert os.path.isdir(directory), f"Directory missing: {directory}"


def test_detector_source_compiles_and_general_algorithm():
    assert os.path.isfile(DETECTOR_SOURCE), f"C source missing: {DETECTOR_SOURCE}"
    assert os.path.isfile(DETECTOR_BIN), f"C executable missing: {DETECTOR_BIN}"
    assert os.access(DETECTOR_BIN, os.X_OK), f"C executable not executable: {DETECTOR_BIN}"
    assert os.path.isfile(PROCESS_SCRIPT), f"Bash script missing: {PROCESS_SCRIPT}"
    assert os.access(PROCESS_SCRIPT, os.X_OK), f"Bash script not executable: {PROCESS_SCRIPT}"

    rebuilt = f"{BIN}/.detector-verifier-{secrets.token_hex(8)}"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", DETECTOR_SOURCE, "-o", rebuilt, "-lm"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"detector.c did not compile with -lm.\nstdout: {compile_result.stdout}\n"
        f"stderr: {compile_result.stderr}"
    )
    os.replace(rebuilt, DETECTOR_BIN)
    assert os.access(DETECTOR_BIN, os.X_OK), "Recompiled detector is not executable"

    no_args = subprocess.run([DETECTOR_BIN], capture_output=True, text=True, timeout=10)
    assert no_args.returncode != 0, "detector must reject calls without exactly two arguments"
    too_many = subprocess.run(
        [DETECTOR_BIN, "/tmp/a", "/tmp/b", "/tmp/c"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert too_many.returncode != 0, "detector must reject calls with more than two arguments"

    base_x = secrets.randbelow(101) - 50
    base_y = secrets.randbelow(101) - 50
    base_ts = 800000 + secrets.randbelow(100000)
    cases = [
        [(base_ts, base_x, base_y)],
        [
            (base_ts + 10, base_x, base_y),
            (base_ts + 20, base_x + 30, base_y + 40),
            (base_ts + 30, base_x + 81, base_y + 40),
            (base_ts + 40, base_x + 81, base_y + 40),
        ],
        make_random_rows(3),
        make_random_rows(7),
        make_random_rows(9),
    ]

    token = secrets.token_hex(10)
    for index, rows in enumerate(cases):
        csv_path = f"/tmp/detector-{token}-{index}.csv"
        out_path = f"/tmp/detector-{token}-{index}.out"
        write_csv(csv_path, rows)
        result = subprocess.run(
            [DETECTOR_BIN, csv_path, out_path],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0, (
            f"Recompiled detector failed on generated case {index}.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert_exact_output(out_path, rows)


def test_detector_compiles_and_process_script_runs():
    assert os.path.isfile(DETECTOR_BIN), f"C executable missing: {DETECTOR_BIN}"
    assert os.access(DETECTOR_BIN, os.X_OK), f"C executable not executable: {DETECTOR_BIN}"
    assert os.path.isfile(PROCESS_SCRIPT), f"Bash script missing: {PROCESS_SCRIPT}"
    assert os.access(PROCESS_SCRIPT, os.X_OK), f"Bash script not executable: {PROCESS_SCRIPT}"

    csv1_path = f"{INPUT}/test1.csv"
    with open(csv1_path, "w") as f:
        f.write("1000,10.0,10.0\n")
        f.write("1001,12.0,11.0\n")
        f.write("1002,100.0,11.0\n")
        f.write("1003,101.0,12.0\n")
        f.write("1004,101.0,90.0\n")

    csv2_path = f"{INPUT}/test2.csv"
    with open(csv2_path, "w") as f:
        f.write("2000,10.0,10.0\n")
        f.write("2001,12.0,11.0\n")

    result = subprocess.run([PROCESS_SCRIPT], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, f"process.sh failed with exit code {result.returncode}\nStderr: {result.stderr}"

    out1_path = f"{OUTPUT}/test1.out"
    assert os.path.isfile(out1_path), f"Output file missing: {out1_path}"
    with open(out1_path, "r") as f:
        out1_content = f.read()
    assert "Mean X: 64.80" in out1_content, f"test1.out missing 'Mean X: 64.80'. Got:\n{out1_content}"
    assert "Mean Y: 26.80" in out1_content, f"test1.out missing 'Mean Y: 26.80'. Got:\n{out1_content}"
    assert "Anomaly Count: 2" in out1_content, f"test1.out missing 'Anomaly Count: 2'. Got:\n{out1_content}"
    assert "Anomaly Timestamps: 1002,1004" in out1_content, f"test1.out missing anomaly timestamps. Got:\n{out1_content}"

    out2_path = f"{OUTPUT}/test2.out"
    assert os.path.isfile(out2_path), f"Output file missing: {out2_path}"
    with open(out2_path, "r") as f:
        out2_content = f.read()
    assert "Mean X: 11.00" in out2_content, f"test2.out missing 'Mean X: 11.00'. Got:\n{out2_content}"
    assert "Mean Y: 10.50" in out2_content, f"test2.out missing 'Mean Y: 10.50'. Got:\n{out2_content}"
    assert "Anomaly Count: 0" in out2_content, f"test2.out missing 'Anomaly Count: 0'. Got:\n{out2_content}"
    assert "Anomaly Timestamps: None" in out2_content, f"test2.out missing 'Anomaly Timestamps: None'. Got:\n{out2_content}"

    assert not os.path.isfile(csv1_path), f"File {csv1_path} was not moved out of input directory"
    assert not os.path.isfile(csv2_path), f"File {csv2_path} was not moved out of input directory"
    assert os.path.isfile(f"{ARCHIVE}/test1.csv"), "test1.csv not found in archive directory"
    assert os.path.isfile(f"{ARCHIVE}/test2.csv"), "test2.csv not found in archive directory"


def test_process_script_on_runtime_generated_files():
    token = secrets.token_hex(10)
    generated = {
        f"runtime_{token}_a": make_random_rows(3),
        f"runtime_{token}_b": make_random_rows(7),
        f"runtime_{token}_c": make_random_rows(9),
    }
    for name, rows in generated.items():
        write_csv(f"{INPUT}/{name}.csv", rows)

    result = subprocess.run([PROCESS_SCRIPT], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, (
        f"process.sh failed on generated inputs with exit code {result.returncode}\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )

    for name, rows in generated.items():
        input_path = f"{INPUT}/{name}.csv"
        archive_path = f"{ARCHIVE}/{name}.csv"
        output_path = f"{OUTPUT}/{name}.out"
        assert not os.path.exists(input_path), f"process.sh left {input_path} in input"
        assert os.path.isfile(archive_path), f"process.sh did not archive {name}.csv"
        assert_exact_output(output_path, rows)


def test_cron_file():
    cron_file = "/home/user/pipeline.cron"
    assert os.path.isfile(cron_file), f"Cron file missing: {cron_file}"
    with open(cron_file, "r") as f:
        content = f.read().strip()

    cron_pattern = r"^(?:\*/5|0,5,10,15,20,25,30,35,40,45,50,55)\s+\*\s+\*\s+\*\s+\*\s+/home/user/pipeline/bin/process\.sh"
    match = False
    for line in content.splitlines():
        if re.search(cron_pattern, line.strip()):
            match = True
            break
    assert match, f"Cron file does not contain the correct 5-minute schedule for process.sh. Got:\n{content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
