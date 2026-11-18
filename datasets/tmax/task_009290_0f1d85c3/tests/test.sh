#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess

RAW_FILE = "/home/user/raw_telemetry.csv"
PROCESSED_FILE = "/home/user/processed_telemetry.csv"
SUMMARY_FILE = "/home/user/summary.txt"
VALUE_RE = re.compile(r"^[+-]?\d+\.\d{2}$")


def compute_expected_data():
    if not os.path.exists(RAW_FILE):
        raise AssertionError(f"Raw file {RAW_FILE} is missing, cannot compute expected state.")

    buckets = {}
    with open(RAW_FILE, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            if len(parts) != 2:
                continue
            ts = int(parts[0])
            val = float(parts[1])

            if val < -50.0 or val > 150.0:
                continue

            bucket_time = (ts // 10) * 10
            buckets.setdefault(bucket_time, []).append(val)

    if not buckets:
        return {}, 0.0, 0.0, 0.0

    avg_buckets = {b: sum(v) / len(v) for b, v in buckets.items()}
    min_b = min(avg_buckets)
    max_b = max(avg_buckets)
    final_series = {}

    for b in range(min_b, max_b + 10, 10):
        if b in avg_buckets:
            final_series[b] = avg_buckets[b]
        else:
            before = b - 10
            while before not in avg_buckets and before >= min_b:
                before -= 10
            after = b + 10
            while after not in avg_buckets and after <= max_b:
                after += 10
            val_before = avg_buckets[before]
            val_after = avg_buckets[after]
            fraction = (b - before) / (after - before)
            final_series[b] = val_before + fraction * (val_after - val_before)

    vals = list(final_series.values())
    return final_series, min(vals), max(vals), sum(vals) / len(vals)


def check_outputs():
    assert os.path.exists(PROCESSED_FILE), f"Output file {PROCESSED_FILE} was not created."
    expected_series, expected_min, expected_max, expected_mean = compute_expected_data()

    with open(PROCESSED_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_series), (
        f"Expected {len(expected_series)} rows in processed CSV, found {len(lines)}."
    )
    expected_sorted_buckets = sorted(expected_series)

    for i, line in enumerate(lines):
        parts = line.split(")") if False else line.split(",")
        assert len(parts) == 2, f"Invalid format in processed CSV at line {i + 1}: '{line}'"
        time_text = parts[0].strip()
        value_text = parts[1].strip()
        assert re.fullmatch(r"[+-]?\d+", time_text), f"Invalid bucket time at line {i + 1}: '{time_text}'"
        assert VALUE_RE.fullmatch(value_text), (
            f"Value at line {i + 1} must be written with exactly two decimal places: '{value_text}'"
        )

        b_time = int(time_text)
        b_val = float(value_text)
        expected_time = expected_sorted_buckets[i]
        expected_val = expected_series[expected_time]
        assert b_time == expected_time, (
            f"Expected bucket time {expected_time} at line {i + 1}, got {b_time}."
        )
        assert f"{b_val:.2f}" == f"{expected_val:.2f}", (
            f"Expected value {expected_val:.2f} for bucket {b_time}, got {b_val:.2f}."
        )

    assert os.path.exists(SUMMARY_FILE), f"Summary file {SUMMARY_FILE} was not created."
    with open(SUMMARY_FILE, "r") as f:
        content = f.read().strip()

    expected_content = (
        f"MIN: {expected_min:.2f}\n"
        f"MAX: {expected_max:.2f}\n"
        f"MEAN: {expected_mean:.2f}"
    )
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    expected_lines = expected_content.splitlines()
    assert len(actual_lines) == len(expected_lines), (
        f"Summary file should have exactly 3 lines, found {len(actual_lines)}."
    )
    for i in range(3):
        assert actual_lines[i] == expected_lines[i], (
            f"Summary mismatch on line {i + 1}. Expected '{expected_lines[i]}', got '{actual_lines[i]}'."
        )


def compile_candidates():
    sources = []
    for root, dirs, files in os.walk("/home/user"):
        for name in files:
            path = os.path.join(root, name)
            if name.endswith(".c") and os.path.isfile(path):
                sources.append(path)
    sources.sort()
    assert sources, "No C source program was found under /home/user."

    source_sets = [sources] + [[source] for source in sources]
    candidates = []
    for i, source_set in enumerate(source_sets):
        exe = f"/tmp/telemetry_candidate_{i}"
        result = subprocess.run(
            ["gcc", "-std=c11", *source_set, "-lm", "-o", exe],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if result.returncode == 0:
            candidates.append(exe)
    assert candidates, "The submitted C source could not be compiled with gcc."
    return candidates


def generated_fixtures():
    rng = random.SystemRandom()
    base1 = rng.randrange(20000, 80000) * 10
    x = rng.randrange(-10, 31) * 2
    case1 = [
        f"{base1 + 2},{x}.0",
        f"{base1 + 8},{x + 4}.0",
        f"{base1 + 11},150.01",
        f"{base1 + 16},-50.01",
        f"{base1 + 22},{x + 12}.0",
        f"{base1 + 41},{x + 24}.0",
        f"{base1 + 48},{x + 28}.0",
        f"{base1 + 61},-50.0",
        f"{base1 + 68},150.0",
    ]

    base2 = rng.randrange(90000, 150000) * 10
    y = rng.randrange(-10, 21)
    case2 = [
        f"{base2 + 72},{y + 31}.0",
        f"{base2 + 1},{y + 1}.0",
        f"{base2 + 35},{y + 15}.0",
        f"{base2 + 9},{y + 5}.0",
        f"{base2 + 44},999.0",
        f"{base2 + 21},-999.0",
    ]
    return [case1, case2]


def candidate_performs_pipeline(exe, fixtures):
    try:
        for rows in fixtures:
            with open(RAW_FILE, "w") as f:
                f.write("\n".join(rows) + "\n")
            for output in (PROCESSED_FILE, SUMMARY_FILE):
                try:
                    os.remove(output)
                except FileNotFoundError:
                    pass
            result = subprocess.run(
                [exe],
                cwd="/home/user",
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=5,
            )
            if result.returncode != 0:
                return False
            check_outputs()
        return True
    except (AssertionError, OSError, subprocess.TimeoutExpired, ValueError):
        return False


def read_optional(path):
    try:
        with open(path, "rb") as f:
            return f.read()
    except FileNotFoundError:
        return None


def restore(path, data):
    if data is None:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    else:
        with open(path, "wb") as f:
            f.write(data)


def main():
    # Preserve and check the agent's required final outputs for the original input.
    original_raw = read_optional(RAW_FILE)
    original_processed = read_optional(PROCESSED_FILE)
    original_summary = read_optional(SUMMARY_FILE)
    try:
        check_outputs()
        candidates = compile_candidates()
        fixtures = generated_fixtures()
        assert any(candidate_performs_pipeline(exe, fixtures) for exe in candidates), (
            "No compiled submitted C program produced correct outputs for generated telemetry inputs."
        )
    finally:
        restore(RAW_FILE, original_raw)
        restore(PROCESSED_FILE, original_processed)
        restore(SUMMARY_FILE, original_summary)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
