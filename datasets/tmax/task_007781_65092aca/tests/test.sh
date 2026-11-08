#!/bin/bash
set -e
mkdir -p /logs/verifier

GCC=/usr/bin/gcc
GCC_REAL=/usr/bin/gcc.verifier-real
RAW=/home/user/raw_sensor.log
RAW_BACKUP=/tmp/raw_sensor.log.verifier-backup

rm -f "$GCC_REAL" /tmp/verifier_gcc_calls /tmp/verifier_program_runs
cp -a "$RAW" "$RAW_BACKUP"
mv "$GCC" "$GCC_REAL"

cleanup() {
    if [ -e "$GCC_REAL" ] || [ -L "$GCC_REAL" ]; then
        rm -f "$GCC"
        mv "$GCC_REAL" "$GCC"
    fi
    if [ -e "$RAW_BACKUP" ]; then
        cp -a "$RAW_BACKUP" "$RAW"
        rm -f "$RAW_BACKUP"
    fi
}
trap cleanup EXIT

cat > "$GCC" <<'GCC_EOF'
#!/bin/bash
echo gcc >> /tmp/verifier_gcc_calls
/usr/bin/gcc.verifier-real "$@"
status=$?
[ "$status" -eq 0 ] || exit "$status"

out=a.out
need_out=0
for arg in "$@"; do
    if [ "$need_out" -eq 1 ]; then
        out=$arg
        need_out=0
    elif [ "$arg" = "-o" ]; then
        need_out=1
    elif [[ "$arg" == -o?* ]]; then
        out=${arg#-o}
    fi
done

if [ -f "$out" ] && [ -x "$out" ]; then
    absolute=$(readlink -m -- "$out")
    real_output="${absolute}.__verifier_real"
    mv -f -- "$out" "$real_output"
    {
        echo '#!/bin/bash'
        echo 'echo run >> /tmp/verifier_program_runs'
        printf 'exec %q "$@"\n' "$real_output"
    } > "$out"
    chmod +x "$out"
fi
exit 0
GCC_EOF
chmod +x "$GCC"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import datetime
import os
import random
import re
import subprocess
import pytest

RAW_PATH = "/home/user/raw_sensor.log"
CSV_PATH = "/home/user/clean_resampled.csv"
ORIGINAL_RAW = open("/tmp/raw_sensor.log.verifier-backup", "r").read()


def test_pipeline_files_exist():
    """Ensure the pipeline script and C program exist."""
    assert os.path.isfile("/home/user/pipeline.sh"), "Missing /home/user/pipeline.sh"
    assert os.path.isfile("/home/user/interpolate.c"), "Missing /home/user/interpolate.c"
    assert os.path.getsize("/home/user/pipeline.sh") > 0, "pipeline.sh is empty"
    assert os.path.getsize("/home/user/interpolate.c") > 0, "interpolate.c is empty"


def iso_time(offset):
    base = datetime.datetime(2023, 10, 1, 12, 0, 0, tzinfo=datetime.timezone.utc)
    return (base + datetime.timedelta(seconds=offset)).strftime("%Y-%m-%dT%H:%M:%SZ")


def expected_at(points, target):
    for x, y in points:
        if x == target:
            return y
    for (x1, y1), (x2, y2) in zip(points, points[1:]):
        if x1 < target < x2:
            return y1 + (target - x1) * (y2 - y1) / (x2 - x1)
    raise AssertionError(f"Target {target} is not bracketed")


def write_log(points, case_number):
    lines = [f"[INFO] {iso_time(0)} - Dynamic test case {case_number}"]
    for index, (offset, value) in enumerate(points):
        if index == 1:
            lines.append(f"[WARN] {iso_time(offset - 1)} - unrelated temp: 9999.0")
        lines.append(
            f'[DATA] {iso_time(offset)} - payload: {{"sensor_id": "T{case_number}", "temp": {value:.3f}}}'
        )
        if index == 2:
            lines.append(f"[DEBUG] {iso_time(offset + 1)} - Network check")
    with open(RAW_PATH, "w") as f:
        f.write("\n".join(lines) + "\n")


def run_pipeline():
    for path in (CSV_PATH, "/tmp/verifier_gcc_calls", "/tmp/verifier_program_runs"):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    result = subprocess.run(
        ["bash", "/home/user/pipeline.sh"],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=25,
    )
    assert result.returncode == 0, (
        f"pipeline.sh failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile("/tmp/verifier_gcc_calls"), "pipeline.sh did not invoke gcc"
    assert os.path.isfile("/tmp/verifier_program_runs"), "pipeline.sh did not run the executable produced by gcc"
    assert os.path.isfile(CSV_PATH), f"Missing output file: {CSV_PATH}"


def verify_dynamic_csv(points):
    with open(CSV_PATH, newline="") as f:
        rows = list(csv.reader(f))
    assert rows[0] == ["timestamp", "temperature"], f"Incorrect CSV header: {rows[0]}"
    assert len(rows) == 5, f"Expected exactly a header and 4 rows, found {len(rows)} rows"
    expected_timestamps = [1696161610, 1696161620, 1696161630, 1696161640]
    observed = []
    for row, timestamp in zip(rows[1:], expected_timestamps):
        assert len(row) == 2, f"Invalid row format: {row}"
        assert row[0] == str(timestamp), f"Expected timestamp {timestamp}, got {row[0]}"
        assert re.fullmatch(r"-?\d+\.\d{2}", row[1]), f"Temperature is not formatted to 2 decimals: {row[1]}"
        observed.append(float(row[1]))
    epoch_base = 1696161600
    for actual, timestamp in zip(observed, expected_timestamps):
        expected = expected_at(points, timestamp - epoch_base)
        assert abs(actual - expected) <= 0.011, (
            f"For timestamp {timestamp}, expected {expected:.2f}, got {actual:.2f}"
        )


def test_pipeline_on_unseen_inputs_and_restore_original_output():
    rng = random.SystemRandom()
    schedules = ([3, 14, 29, 47], [1, 18, 33, 44], [4, 16, 26, 49])
    try:
        for case_number, offsets in enumerate(schedules, 1):
            values = [rng.randint(-2500, 6500) / 100.0 for _ in offsets]
            points = list(zip(offsets, values))
            write_log(points, case_number)
            run_pipeline()
            verify_dynamic_csv(points)
    finally:
        with open(RAW_PATH, "w") as f:
            f.write(ORIGINAL_RAW)
    run_pipeline()


def test_csv_output_exists():
    """Ensure the output CSV file is created."""
    csv_path = "/home/user/clean_resampled.csv"
    assert os.path.isfile(csv_path), f"Missing output file: {csv_path}"


def test_csv_output_content():
    """Ensure the output CSV contains the correct interpolated values."""
    csv_path = "/home/user/clean_resampled.csv"
    if not os.path.isfile(csv_path):
        pytest.fail(f"File {csv_path} does not exist.")

    with open(csv_path, "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) >= 5, f"Expected at least a header and 4 rows, found {len(rows)} rows."

    # Check header
    assert rows[0] == ["timestamp", "temperature"], f"Incorrect CSV header: {rows[0]}"

    # Expected values
    expected = {
        "1696161610": 18.00,
        "1696161620": 20.33,
        "1696161630": 15.00,
        "1696161640": 25.00
    }

    parsed_data = {}
    for row in rows[1:]:
        if not row:
            continue
        assert len(row) == 2, f"Invalid row format: {row}"
        ts, temp_str = row
        try:
            parsed_data[ts] = float(temp_str)
        except ValueError:
            pytest.fail(f"Invalid temperature value: {temp_str}")

    for ts, expected_temp in expected.items():
        assert ts in parsed_data, f"Missing timestamp {ts} in output CSV."
        actual_temp = parsed_data[ts]
        assert abs(actual_temp - expected_temp) < 0.05, f"For timestamp {ts}, expected temp ~{expected_temp:.2f}, got {actual_temp}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
