#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import subprocess

AGENT_PATH = "/home/user/detector.py"
REPORT_PATH = "/home/user/final_report.txt"
ERROR_LOG_PATH = "/home/user/pipeline_errors.log"
LINE_RE = re.compile(r"^\d+,[A-Za-z]+,\d+(?:\.\d+)?$")


def expected_output(inp):
    history = {}
    anomalies = {}
    stdout = []
    stderr = []

    for line_with_ending in inp.splitlines(keepends=True):
        line = line_with_ending[:-1] if line_with_ending.endswith("\n") else line_with_ending
        if not LINE_RE.fullmatch(line):
            stderr.append(f"[ERROR] Invalid line: {line}\n")
            continue

        frame_text, metric, value_text = line.split(",")
        value = float(value_text)
        if metric not in history:
            history[metric] = []
            anomalies[metric] = 0

        hist = history[metric]
        is_anomaly = False
        if len(hist) == 3:
            average = sum(hist) / 3.0
            if abs(value - average) > 15.0:
                stdout.append(
                    f"ANOMALY at frame {int(frame_text)}: {metric} = {value:.2f} "
                    f"(avg = {average:.2f})\n"
                )
                anomalies[metric] += 1
                is_anomaly = True

        if not is_anomaly:
            hist.append(value)
            if len(hist) > 3:
                hist.pop(0)

    stdout.append("SUMMARY:\n")
    for metric in sorted(anomalies):
        stdout.append(f"{metric}: {anomalies[metric]}\n")
    return "".join(stdout), "".join(stderr)


def run_agent(inp):
    proc = subprocess.run(
        ["python3", AGENT_PATH],
        input=inp,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert proc.returncode == 0, f"detector exited with {proc.returncode}: {proc.stderr}"
    return proc.stdout, proc.stderr


def generate_fuzz_input(rng):
    lines = []
    metrics = ["YAVG", "TEMP", "PRES", "VOLT", "A", "b", "c"]
    for _ in range(rng.randint(0, 250)):
        if rng.random() < 0.8:
            frame = rng.randint(0, 10000)
            metric = rng.choice(metrics)
            if rng.random() < 0.5:
                value = str(rng.randint(0, 255))
            else:
                value = str(round(rng.uniform(0.0, 255.0), 3))
            lines.append(f"{frame},{metric},{value}")
        else:
            lines.append(rng.choice([
                "bad,YAVG,10",
                "15,YAVG-2,10",
                "16,YAVG,10.0.0",
                "12 YAVG 10",
                "12,YAVG123,10.5",
                "-1,YAVG,10",
                "1,YAVG,-10",
                "1,YAVG,.5",
                "1,YAVG,5.",
            ]))
    return ("\n".join(lines) + "\n") if lines else ""


def test_detector_exists_and_matches_specification():
    assert os.path.isfile(AGENT_PATH), f"Detector script not found at {AGENT_PATH}"

    cases = [
        "",
        "1,YAVG,10\n2,YAVG,10\n3,YAVG,10\n4,YAVG,25\n5,YAVG,25.001\n",
        "1,Z,10\n2,Z,20\n3,Z,30\n4,Z,5\n5,Z,100\n6,Z,20\n",
        "1,b,1\n2,A,2\n3,b,1\n4,b,1\n5,b,17\ninvalid\n",
        "1,YAVG,10\n2,YAVG,10\n3,YAVG,10\n4,YAVG,40\n5,YAVG,10\n",
    ]

    rng = random.Random(42)
    cases.extend(generate_fuzz_input(rng) for _ in range(150))

    for inp in cases:
        expected_stdout, expected_stderr = expected_output(inp)
        actual_stdout, actual_stderr = run_agent(inp)
        assert actual_stdout == expected_stdout, (
            f"Stdout mismatch on input:\n{inp}\n"
            f"Expected:\n{expected_stdout}\nActual:\n{actual_stdout}"
        )
        assert actual_stderr == expected_stderr, (
            f"Stderr mismatch on input:\n{inp}\n"
            f"Expected:\n{expected_stderr}\nActual:\n{actual_stderr}"
        )


def extract_yavg_values():
    proc = subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-nostdin", "-i", "/app/telemetry.mp4",
            "-vf", "signalstats,metadata=print:key=lavfi.signalstats.YAVG",
            "-f", "null", "-",
        ],
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert proc.returncode == 0, f"ffmpeg signalstats failed: {proc.stderr}"

    frames = []
    current_frame = None
    for line in (proc.stdout + "\n" + proc.stderr).splitlines():
        frame_match = re.search(r"\bframe:\s*(\d+)\b", line)
        if frame_match:
            current_frame = int(frame_match.group(1))
        value_match = re.search(r"lavfi\.signalstats\.YAVG=([0-9]+(?:\.[0-9]+)?)", line)
        if value_match and current_frame is not None:
            frames.append((current_frame, value_match.group(1)))
            current_frame = None

    assert frames, "No YAVG frame data was extracted from telemetry.mp4"
    return frames


def test_pipeline_outputs_are_real_and_correct():
    assert os.path.isfile(REPORT_PATH), f"Expected output file {REPORT_PATH} is missing."
    assert os.path.isfile(ERROR_LOG_PATH), f"Expected error file {ERROR_LOG_PATH} is missing."

    frames = extract_yavg_values()
    zero_based_csv = "".join(f"{frame},YAVG,{value}\n" for frame, value in frames)
    one_based_csv = "".join(f"{frame + 1},YAVG,{value}\n" for frame, value in frames)
    expected_zero, _ = expected_output(zero_based_csv)
    expected_one, _ = expected_output(one_based_csv)

    with open(REPORT_PATH, "r", encoding="utf-8") as report_file:
        report = report_file.read()

    assert report in (expected_zero, expected_one), (
        "final_report.txt does not match detector output for the YAVG values "
        "actually extracted from telemetry.mp4"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
