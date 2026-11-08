#!/bin/bash
set -u
mkdir -p /logs/verifier

ORIGINAL_ACCESS=$(mktemp)
ORIGINAL_ANOMALIES=$(mktemp)
ORIGINAL_DEBUG=$(mktemp)
cp /home/user/access.log "$ORIGINAL_ACCESS"
HAVE_ANOMALIES=0
HAVE_DEBUG=0

cleanup() {
    set +e
    cp "$ORIGINAL_ACCESS" /home/user/access.log
    if [ "$HAVE_ANOMALIES" -eq 1 ]; then
        cp "$ORIGINAL_ANOMALIES" /home/user/anomalies.log
    else
        rm -f /home/user/anomalies.log
    fi
    if [ "$HAVE_DEBUG" -eq 1 ]; then
        cp "$ORIGINAL_DEBUG" /home/user/debug_counts.txt
    else
        rm -f /home/user/debug_counts.txt
    fi
    rm -f "$ORIGINAL_ACCESS" "$ORIGINAL_ANOMALIES" "$ORIGINAL_DEBUG"
}
trap cleanup EXIT

rm -f /home/user/anomalies.log /home/user/debug_counts.txt
INITIAL_RUN_OK=1
if ! timeout 20s /home/user/analyze_logs.sh >/tmp/analyze_logs.stdout 2>/tmp/analyze_logs.stderr; then
    INITIAL_RUN_OK=0
fi

if [ -f /home/user/anomalies.log ]; then
    cp /home/user/anomalies.log "$ORIGINAL_ANOMALIES"
    HAVE_ANOMALIES=1
fi
if [ -f /home/user/debug_counts.txt ]; then
    cp /home/user/debug_counts.txt "$ORIGINAL_DEBUG"
    HAVE_DEBUG=1
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess


def get_expected_results():
    access_log = "/home/user/access.log"
    if not os.path.exists(access_log):
        return 0, []

    with open(access_log, "r") as f:
        lines = f.readlines()

    api_lines = [line for line in lines if "/api/v1/process" in line]

    error_times = []
    for line in api_lines:
        parts = line.split()
        if len(parts) >= 2:
            status = parts[-3]
            if status in ("500", "502"):
                try:
                    error_times.append(float(parts[-1]))
                except ValueError:
                    pass

    count = len(error_times)
    if count == 0:
        return 0, []

    mean = sum(error_times) / count
    var = sum((x - mean) ** 2 for x in error_times) / count
    stddev = math.sqrt(var)
    threshold = mean + 2 * stddev

    expected_anomalies = []
    for line in api_lines:
        parts = line.split()
        try:
            val = float(parts[-1])
            if val > threshold:
                expected_anomalies.append(line.strip())
        except ValueError:
            pass

    return count, expected_anomalies


def test_debug_counts_file():
    """Verify that debug_counts.txt contains the correct filtered 5xx error count."""
    debug_file = "/home/user/debug_counts.txt"
    assert os.path.exists(debug_file), f"Missing file: {debug_file}. The script must create this file."

    expected_count, _ = get_expected_results()
    expected_text = f"Filtered 5xx error count: {expected_count}"

    with open(debug_file, "r") as f:
        content = f.read().strip()

    assert content == expected_text, f"Incorrect content in {debug_file}. Expected '{expected_text}', got '{content}'."


def test_anomalies_file():
    """Verify that anomalies.log contains the correct anomalous log lines."""
    anomalies_file = "/home/user/anomalies.log"
    assert os.path.exists(anomalies_file), f"Missing file: {anomalies_file}. The script must create this file."

    _, expected_anomalies = get_expected_results()

    with open(anomalies_file, "r") as f:
        actual_anomalies = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_anomalies == expected_anomalies, (
        f"Incorrect anomalies recorded. Expected {len(expected_anomalies)} lines, "
        f"found {len(actual_anomalies)}. Check your filtering and variance calculation."
    )


def test_script_is_executable():
    """Verify that analyze_logs.sh is executable."""
    script_file = "/home/user/analyze_logs.sh"
    assert os.path.exists(script_file), f"Missing file: {script_file}"
    assert os.access(script_file, os.X_OK), f"File is not executable: {script_file}"


def test_script_is_bash():
    script_file = "/home/user/analyze_logs.sh"
    with open(script_file, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace").strip()
    assert first_line in ("#!/bin/bash", "#!/usr/bin/bash", "#!/usr/bin/env bash"), (
        "analyze_logs.sh must be an executable Bash script"
    )


def test_script_processes_runtime_log_fixture():
    rng = secrets.SystemRandom()
    base = rng.randint(850, 1150)
    token = secrets.token_hex(4)
    offsets = [0.01, 0.02, 0.01, 0.03, 0.02, 0.01, 0.02, 0.03, 0.05]
    lines = []

    for i, offset in enumerate(offsets):
        protocol = "HTTP/2.0" if i in (1, 8) else "HTTP/1.1"
        status = "502" if i in (1, 8) else "500"
        lines.append(
            f"172.16.0.{i + 1} - - [11/Oct/2023:13:{i:02d}:00 -0700] "
            f"\"POST /api/v1/process {protocol}\" {status} 1234 {base + offset:.2f}"
        )

    lines.extend([
        f"10.20.0.1 - - [11/Oct/2023:14:00:00 -0700] \"POST /api/v1/process HTTP/1.1\" 200 100 {base + 0.06:.2f}",
        f"10.20.0.2 - - [11/Oct/2023:14:01:00 -0700] \"GET /api/v1/process HTTP/2.0\" 404 100 {base + 0.07:.2f}",
        f"10.20.0.3 - - [11/Oct/2023:14:02:00 -0700] \"POST /api/v1/process HTTP/1.1\" 200 100 {base - 1.00:.2f}",
        f"10.20.0.4 - - [11/Oct/2023:14:03:00 -0700] \"GET /unrelated/{token} HTTP/2.0\" 502 100 {base + 50.00:.2f}",
    ])
    rng.shuffle(lines)

    with open("/home/user/access.log", "w") as f:
        f.write("\n".join(lines) + "\n")

    expected_count, expected_anomalies = get_expected_results()
    os.remove("/home/user/anomalies.log") if os.path.exists("/home/user/anomalies.log") else None
    os.remove("/home/user/debug_counts.txt") if os.path.exists("/home/user/debug_counts.txt") else None

    subprocess.run(
        ["/home/user/analyze_logs.sh"],
        cwd="/home/user",
        check=True,
        timeout=20,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    with open("/home/user/debug_counts.txt", "r") as f:
        actual_debug = f.read().strip()
    assert actual_debug == f"Filtered 5xx error count: {expected_count}"

    with open("/home/user/anomalies.log", "r") as f:
        actual_anomalies = [line.strip() for line in f if line.strip()]
    assert actual_anomalies == expected_anomalies
TEST_EOF

if [ "$INITIAL_RUN_OK" -eq 1 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
