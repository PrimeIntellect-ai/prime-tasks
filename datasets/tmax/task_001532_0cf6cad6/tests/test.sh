#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import stat
import subprocess

HOME = "/home/user"


def test_aggregate_cpp_exists():
    path = "/home/user/aggregate.cpp"
    assert os.path.isfile(path), f"File {path} is missing. The C++ program source code must be created."


def test_pipeline_sh_exists_and_executable():
    path = "/home/user/pipeline.sh"
    assert os.path.isfile(path), f"File {path} is missing. The ETL pipeline script must be created."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable. Make sure to run chmod +x on it."


def test_summary_csv_exists_and_correct():
    path = "/home/user/summary.csv"
    assert os.path.isfile(path), f"File {path} is missing. The pipeline must generate this output file."

    with open(path, "r") as f:
        content = f.read().strip()

    expected_content = (
        "S1,10000000.250000,0.016667\n"
        "S2,50000000.525000,0.002500"
    )

    assert content == expected_content, (
        f"Contents of {path} do not match the expected output.\n"
        f"Expected:\n{expected_content}\n\nGot:\n{content}\n"
        "Check your data cleaning logic and ensure your C++ variance calculation is numerically stable."
    )


def expected_output(groups):
    lines = []
    for sensor_id in sorted(groups):
        count = 0
        mean = 0.0
        m2 = 0.0
        for value in groups[sensor_id]:
            count += 1
            delta = value - mean
            mean += delta / count
            delta2 = value - mean
            m2 += delta * delta2
        variance = m2 / (count - 1)
        lines.append(f"{sensor_id},{mean:.6f},{variance:.6f}")
    return "\n".join(lines)


def assert_strict_output(actual, expected):
    actual = actual.strip()
    for line in actual.splitlines():
        assert re.fullmatch(r"[^,]+,-?[0-9]+\.[0-9]{6},-?[0-9]+\.[0-9]{6}", line), (
            f"Output line is not in sensor_id,mean,variance format with exactly six decimals: {line!r}"
        )
    assert actual == expected, f"Expected:\n{expected}\n\nGot:\n{actual}"


def make_groups():
    rng = random.SystemRandom()
    groups = {}
    for sensor_id, count in (("ALPHA", 9), ("BETA", 7), ("OMEGA", 11)):
        baseline = rng.randrange(10_000_000, 90_000_000)
        offsets = [rng.randrange(-20, 21) / 8.0 for _ in range(count)]
        if len(set(offsets)) == 1:
            offsets[-1] += 0.125
        groups[sensor_id] = [baseline + offset for offset in offsets]
    return groups


def test_compiled_aggregate_on_derived_high_baseline_data():
    binary = "/tmp/submitted_aggregate"
    result = subprocess.run(
        ["g++", "-std=c++17", "-O3", "/home/user/aggregate.cpp", "-o", binary],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"aggregate.cpp failed to compile:\n{result.stderr}"

    groups = make_groups()
    rows = []
    timestamp = 1700000000
    max_len = max(map(len, groups.values()))
    for index in range(max_len):
        for sensor_id in reversed(sorted(groups)):
            if index < len(groups[sensor_id]):
                rows.append(f"{timestamp},{sensor_id},{groups[sensor_id][index]:.3f}")
                timestamp += 1
    input_data = "\n".join(rows) + "\n"

    run = subprocess.run(
        [binary], input=input_data, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    )
    assert run.returncode == 0, f"Compiled aggregate program failed:\n{run.stderr}"
    assert_strict_output(run.stdout, expected_output(groups))


def test_pipeline_rebuilds_and_processes_new_raw_data():
    raw_path = os.path.join(HOME, "raw_sensors.csv")
    aggregate_path = os.path.join(HOME, "aggregate")
    with open(raw_path, "rb") as f:
        original_raw = f.read()

    groups = make_groups()
    rows = ["timestamp,sensor_id,value"]
    timestamp = 1800000000
    max_len = max(map(len, groups.values()))
    for index in range(max_len):
        for sensor_id in sorted(groups, reverse=True):
            if index < len(groups[sensor_id]):
                rows.append(f"{timestamp},{sensor_id},{groups[sensor_id][index]:.3f}")
                timestamp += 1
    rows.extend([
        f"{timestamp},BROKEN,ERR",
        f"{timestamp + 1},BROKEN,NaN",
        f"{timestamp + 2},BROKEN,",
    ])

    try:
        with open(raw_path, "w") as f:
            f.write("\n".join(rows) + "\n")
        if os.path.exists(aggregate_path):
            os.remove(aggregate_path)
        summary_path = os.path.join(HOME, "summary.csv")
        if os.path.exists(summary_path):
            os.remove(summary_path)

        run = subprocess.run(
            ["/home/user/pipeline.sh"], cwd=HOME, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=40
        )
        assert run.returncode == 0, f"pipeline.sh failed:\n{run.stderr}"
        assert os.path.isfile(aggregate_path), "pipeline.sh did not build /home/user/aggregate"
        assert os.access(aggregate_path, os.X_OK), "The built aggregate is not executable"
        with open(aggregate_path, "rb") as f:
            assert f.read(4) == b"\x7fELF", "pipeline.sh did not produce a compiled executable"
        assert os.path.isfile(summary_path), "pipeline.sh did not generate /home/user/summary.csv"
        with open(summary_path) as f:
            actual = f.read()
        assert "BROKEN" not in actual, "Invalid numeric rows were not filtered out"
        assert_strict_output(actual, expected_output(groups))
    finally:
        with open(raw_path, "wb") as f:
            f.write(original_raw)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
