#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import glob
import pwd
import random
import secrets
import subprocess


def expected_output(input_file):
    with open(input_file, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        metrics = {"cpu": [], "memory": [], "disk": []}
        records = []
        for row in reader:
            ts = int(row["timestamp"])
            for m in ["cpu", "memory", "disk"]:
                val = float(row[m])
                if val >= 0.0:
                    metrics[m].append(val)
                    records.append({"timestamp": ts, "metric": m, "value": val})

    stats = {}
    for m, vals in metrics.items():
        n = len(vals)
        if n == 0:
            continue
        mean = sum(vals) / n
        variance = sum((x - mean) ** 2 for x in vals) / n
        stats[m] = {"mean": mean, "stddev": math.sqrt(variance)}

    anomalies = []
    for record in records:
        metric = record["metric"]
        if abs(record["value"] - stats[metric]["mean"]) > 2 * stats[metric]["stddev"]:
            anomalies.append(record)

    anomalies.sort(key=lambda x: (x["timestamp"], x["metric"]))
    result = [["timestamp", "metric", "value"]]
    for anomaly in anomalies:
        result.append([
            str(anomaly["timestamp"]),
            anomaly["metric"],
            f"{anomaly['value']:.1f}",
        ])
    return result


def test_anomalies_file_exists_and_correct():
    input_file = "/home/user/system_metrics.csv"
    output_file = "/home/user/anomalies.csv"

    assert os.path.exists(output_file), f"Output file {output_file} does not exist."
    assert os.path.exists(input_file), f"Input file {input_file} is missing."

    expected_rows = expected_output(input_file)

    with open(output_file, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) > 0, f"{output_file} is empty."
    assert actual_rows[0] == expected_rows[0], f"Header row in {output_file} is incorrect."
    assert actual_rows == expected_rows, f"Anomalies in {output_file} do not match the expected values."


def test_cpp_source_compiles_and_processes_fresh_input():
    input_file = "/home/user/system_metrics.csv"
    output_file = "/home/user/anomalies.csv"

    candidates = []
    for extension in ("*.cpp", "*.cc", "*.cxx"):
        candidates.extend(glob.glob("/home/user/**/" + extension, recursive=True))
    candidates = sorted({p for p in candidates if os.path.isfile(p)})
    assert candidates, "No C++ source file was written under /home/user."

    with open(input_file, "rb") as f:
        original_input = f.read()
    original_output = None
    if os.path.exists(output_file):
        with open(output_file, "rb") as f:
            original_output = f.read()

    rng = random.Random(secrets.randbits(128))
    timestamps = rng.sample(range(100, 10000), 12)
    cpu_base = float(rng.randint(30, 70))
    memory_base = float(rng.randint(1200, 3500))
    disk_base = float(rng.randint(50, 250))

    rows = []
    for i, timestamp in enumerate(timestamps):
        cpu = cpu_base
        memory = memory_base
        disk = disk_base
        if i == 3:
            cpu += float(rng.randint(500, 900))
            memory += float(rng.randint(5000, 9000))
        if i == 8:
            disk += float(rng.randint(1000, 1800))
        if i == 1:
            cpu = -float(rng.randint(1, 50))
        if i == 5:
            memory = -float(rng.randint(1, 50))
        if i == 10:
            disk = -float(rng.randint(1, 50))
        rows.append([timestamp, cpu, memory, disk])
    rng.shuffle(rows)

    user = pwd.getpwnam("user")

    def demote():
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    errors = []
    try:
        with open(input_file, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["timestamp", "cpu", "memory", "disk"])
            writer.writerows(rows)
        expected_rows = expected_output(input_file)

        for index, source in enumerate(candidates):
            executable = f"/tmp/submitted_metrics_{index}"
            try:
                compilation = subprocess.run(
                    ["g++", "-std=c++17", "-O2", source, "-o", executable],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=30,
                )
                if compilation.returncode != 0:
                    errors.append(f"{source}: compilation failed: {compilation.stderr[-1000:]}")
                    continue

                if os.path.exists(output_file):
                    os.remove(output_file)
                execution = subprocess.run(
                    [executable],
                    cwd="/home/user",
                    env={**os.environ, "HOME": "/home/user"},
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=15,
                    preexec_fn=demote,
                )
                if execution.returncode != 0:
                    errors.append(f"{source}: executable returned {execution.returncode}: {execution.stderr[-1000:]}")
                    continue
                if not os.path.exists(output_file):
                    errors.append(f"{source}: executable did not create {output_file}")
                    continue

                with open(output_file, "r", encoding="utf-8") as f:
                    actual_rows = list(csv.reader(f))
                if actual_rows == expected_rows:
                    return
                errors.append(f"{source}: output on fresh input was incorrect")
            except (subprocess.TimeoutExpired, OSError) as exc:
                errors.append(f"{source}: {exc}")
            finally:
                if os.path.exists(executable):
                    os.remove(executable)

        raise AssertionError("No submitted C++ source compiled and produced the correct dynamic output. " + " | ".join(errors))
    finally:
        with open(input_file, "wb") as f:
            f.write(original_input)
        if original_output is None:
            if os.path.exists(output_file):
                os.remove(output_file)
        else:
            with open(output_file, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
