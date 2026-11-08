#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import stat
import subprocess
from pathlib import Path

SCRIPT = Path("/home/user/analyze.sh")
INPUT = Path("/home/user/requests.jsonl")
OUTPUT = Path("/home/user/rolling_latency.csv")

ORIGINAL_INPUT = """{"ts": 1600000002, "lat": 10}
{"ts": 1600000005, "lat": 20}
{"ts": 1600000022, "lat": 50}
{"ts": 1600000035, "lat": 100}
{"ts": 1600000036, "lat": 200}
{"ts": 1600000060, "lat": 10}
"""


def run_script(input_text):
    assert SCRIPT.exists(), f"Required script {SCRIPT} does not exist"
    assert stat.S_ISREG(os.lstat(SCRIPT).st_mode), f"{SCRIPT} must be a regular file"

    INPUT.write_text(input_text)
    if OUTPUT.exists() or OUTPUT.is_symlink():
        OUTPUT.unlink()

    result = subprocess.run(
        ["bash", str(SCRIPT)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Running bash {SCRIPT} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert OUTPUT.is_file(), f"Output file {OUTPUT} was not created by the script"
    return OUTPUT.read_text().strip()


def test_rolling_latency_output():
    """Test the supplied input and preserve the original exact-output assertions."""
    actual = run_script(ORIGINAL_INPUT)

    expected = """interval_ts,count,avg_lat,mavg_30s
1600000000,2,15.00,15.00
1600000010,0,0.00,15.00
1600000020,1,50.00,26.67
1600000030,2,150.00,116.67
1600000040,0,0.00,116.67
1600000050,0,0.00,150.00
1600000060,1,10.00,10.00"""

    actual_lines = actual.split('\n')
    expected_lines = expected.split('\n')

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in CSV, got {len(actual_lines)}. "
        f"Ensure all intervals from min to max are included, including empty ones."
    )

    for i, (act, exp) in enumerate(zip(actual_lines, expected_lines)):
        assert act.strip() == exp.strip(), (
            f"Mismatch on line {i+1} of {OUTPUT}:\n"
            f"Expected: {exp}\n"
            f"Got:      {act}\n"
            f"Check your rolling aggregation logic and decimal formatting."
        )


def test_script_on_generated_input():
    """Exercise the script on fresh data whose expected report is derived here."""
    rng = random.SystemRandom()
    bucket_count = rng.randint(8, 12)
    base = rng.randint(165000000, 185000000) * 10

    counts = [rng.randint(0, 4) for _ in range(bucket_count)]
    counts[0] = rng.randint(1, 4)
    counts[-1] = rng.randint(1, 4)

    # 27720 is divisible by every possible one- or three-bucket request count
    # (1..12), so all expected averages are exact integers while data vary.
    records = []
    sums = []
    for index, count in enumerate(counts):
        bucket_sum = 0
        for _ in range(count):
            latency = 27720 * rng.randint(1, 20)
            bucket_sum += latency
            records.append({
                "ts": base + index * 10 + rng.randint(0, 9),
                "lat": latency,
            })
        sums.append(bucket_sum)

    rng.shuffle(records)
    input_text = "".join(json.dumps(record, separators=(",", ":")) + "\n" for record in records)
    actual = run_script(input_text)

    expected_lines = ["interval_ts,count,avg_lat,mavg_30s"]
    for index in range(bucket_count):
        count = counts[index]
        avg = sums[index] // count if count else 0
        start = max(0, index - 2)
        rolling_count = sum(counts[start:index + 1])
        rolling_sum = sum(sums[start:index + 1])
        moving = rolling_sum // rolling_count if rolling_count else 0
        expected_lines.append(
            f"{base + index * 10},{count},{avg:.2f},{moving:.2f}"
        )

    actual_lines = actual.split("\n")
    assert actual_lines == expected_lines, (
        "Generated-input report was incorrect.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Got:\n{actual}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
