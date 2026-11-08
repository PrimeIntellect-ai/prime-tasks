#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess


def levenshtein(s1, s2):
    if len(s1) < len(s2):
        return levenshtein(s2, s1)
    if len(s2) == 0:
        return len(s1)
    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row
    return previous_row[-1]


def get_expected_summary(raw_data_path):
    valid_sensors = ["alpha_sensor", "beta_sensor", "gamma_sensor"]
    pattern = re.compile(r"^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}),([a-zA-Z_]+),([0-9]+(\.[0-9]+)?)$")
    parsed_rows = []
    prev_row = None

    with open(raw_data_path, "r") as f:
        for line in f:
            line = line.strip("\n")
            match = pattern.match(line)
            if not match:
                continue

            timestamp = match.group(1)
            sensor_id_raw = match.group(2)
            value = float(match.group(3))
            min_dist = float("inf")
            mapped_sensor = None
            for valid_sensor in valid_sensors:
                distance = levenshtein(sensor_id_raw, valid_sensor)
                if distance < min_dist:
                    min_dist = distance
                    mapped_sensor = valid_sensor

            if min_dist > 2:
                continue

            current_row = (timestamp, mapped_sensor, value)
            if prev_row == current_row:
                continue
            parsed_rows.append(current_row)
            prev_row = current_row

    buckets = {}
    for timestamp, sensor, value in parsed_rows:
        bucketed_hour = timestamp[:14] + "00:00"
        buckets.setdefault((bucketed_hour, sensor), []).append(value)

    expected_lines = []
    for bucketed_hour, sensor in sorted(buckets):
        values = buckets[(bucketed_hour, sensor)]
        expected_lines.append(
            f"[{bucketed_hour}] {sensor} AVG:{sum(values) / len(values):.2f}"
        )
    return expected_lines


def test_c_source_exists():
    assert os.path.exists("/home/user/etl_processor.c"), "/home/user/etl_processor.c does not exist."


def test_c_binary_exists_and_executable():
    binary = "/home/user/etl_processor"
    assert os.path.exists(binary), "/home/user/etl_processor does not exist."
    assert os.access(binary, os.X_OK), "/home/user/etl_processor is not executable."
    with open(binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/etl_processor is not a compiled executable."


def test_summary_txt_correct():
    raw_data_path = "/home/user/raw_data.csv"
    summary_path = "/home/user/summary.txt"

    assert os.path.exists(raw_data_path), f"{raw_data_path} is missing."
    assert os.path.exists(summary_path), f"{summary_path} was not generated."
    expected_lines = get_expected_summary(raw_data_path)
    with open(summary_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == expected_lines, (
        f"Contents of {summary_path} do not match the expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def run_and_check(executable, raw_text):
    raw_path = "/home/user/raw_data.csv"
    summary_path = "/home/user/summary.txt"
    with open(raw_path, "w") as f:
        f.write(raw_text)
    if os.path.exists(summary_path):
        os.remove(summary_path)

    expected = get_expected_summary(raw_path)
    result = subprocess.run(
        [executable], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}. stderr: "
        f"{result.stderr.decode(errors='replace')}"
    )
    assert os.path.exists(summary_path), f"{executable} did not generate summary.txt"
    with open(summary_path, "r") as f:
        actual = f.read().splitlines()
    assert actual == expected, (
        f"{executable} produced incorrect output for a verifier-generated input.\n"
        f"Expected: {expected}\nActual: {actual}"
    )


def test_processor_and_source_on_generated_inputs():
    source_path = "/home/user/etl_processor.c"
    rebuilt_path = "/tmp/etl_processor_rebuilt"
    with open(source_path, "r", errors="replace") as f:
        source = f.read()
    assert re.search(r"#\s*include\s*[<\"]regex\.h[>\"]", source), "C source must include POSIX regex.h."
    assert re.search(r"\bregcomp\s*\(", source), "C source must compile a POSIX regular expression."
    assert re.search(r"\bregexec\s*\(", source), "C source must execute a POSIX regular expression."

    build = subprocess.run(
        ["gcc", "-o", rebuilt_path, source_path],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert build.returncode == 0, (
        "etl_processor.c does not compile with standard gcc: "
        + build.stderr.decode(errors="replace")
    )

    raw_path = "/home/user/raw_data.csv"
    summary_path = "/home/user/summary.txt"
    with open(raw_path, "rb") as f:
        original_raw = f.read()
    original_summary = None
    if os.path.exists(summary_path):
        with open(summary_path, "rb") as f:
            original_summary = f.read()

    rng = secrets.SystemRandom()
    year = rng.randrange(2027, 2090)
    month = rng.randrange(1, 13)
    day = rng.randrange(1, 28)
    date = f"{year:04d}-{month:02d}-{day:02d}"
    value = rng.randrange(11, 80)
    beta_value = rng.randrange(81, 150)
    gamma_value = rng.randrange(3, 40)

    generated = "\n".join([
        f"{date}T18:41:09,alpha_sensor,{value}",
        "not,a,valid,row",
        f"{date}T18:41:09,alpa_sensor,{value}.0",
        f"{date}T03:05:01,beta_sensor,{beta_value}",
        f"{date}T18:42:10,alpha_sensor,{value}",
        f"{date}T18:55:59,apha_senor,{value + 3}",
        f"{date}T03:05:01,bet_sensor,{beta_value}.0",
        f"{date}T03:05:01,beta_sensor,{beta_value}",
        f"{date}T21:00:00,gamma_sensor,{gamma_value}",
        f"{date}T21:12:00,gama_sensor,{gamma_value + 1}",
        f"{date}T21:12:00,gama_sensor,{gamma_value + 1}",
        f"{date}T09:00:00,unknown_thing,999",
        f"{date}T09:00:00,alpha-sensor,12",
        f"{date}T09:00:00,alpha_sensor,+12",
        f"{date}T09:00:00,alpha_sensor,12.",
        f"{date}T09:00:00,alpha_sensor,.5",
        f"{date}T09:00:00,alpha_sensor,1e2",
    ]) + "\n"

    empty_case = "\n".join([
        "invalid_line_no_regex_match",
        f"{date}T01:02:03,faraway_device,50",
        f"{date}T01:02:03,alpha_sensor,-5",
        f"{date}T01:02:03,alpha sensor,5",
    ]) + "\n"

    try:
        for executable in ("/home/user/etl_processor", rebuilt_path):
            run_and_check(executable, generated)
            run_and_check(executable, empty_case)
    finally:
        with open(raw_path, "wb") as f:
            f.write(original_raw)
        if original_summary is None:
            if os.path.exists(summary_path):
                os.remove(summary_path)
        else:
            with open(summary_path, "wb") as f:
                f.write(original_summary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
