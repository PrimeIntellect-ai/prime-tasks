#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY' > /tmp/test_final_state.py
import csv
import io
import json
import math
import os
import random
import secrets
import subprocess

AGENT_PATH = "/home/user/detector.py"
ORACLE_PATH = "/app/legacy_detector"
MISSING = object()


def expected_output(records):
    out = io.StringIO(newline="")
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(["ts", "metric", "mean", "std", "anomaly", "clean_msg"])

    last_valid = None
    window = []
    for ts, metric, msg in records:
        if metric is None:
            metric = last_valid
        else:
            last_valid = metric

        window.append(metric)
        if len(window) > 5:
            window.pop(0)
        values = [x for x in window if x is not None]

        mean = sum(values) / len(values) if values else None
        if len(values) >= 2:
            variance = sum((x - mean) ** 2 for x in values) / (len(values) - 1)
            std = math.sqrt(variance)
        else:
            std = None

        anomaly = (
            metric is not None
            and std is not None
            and abs(metric - mean) > 2.0 * std
        )
        writer.writerow([
            str(ts),
            "" if metric is None else f"{metric:.4f}",
            "" if mean is None else f"{mean:.4f}",
            "" if std is None else f"{std:.4f}",
            "true" if anomaly else "false",
            msg,
        ])
    return out.getvalue().encode("utf-8")


def encode_line(ts, metric, msg, invalid_escape=None):
    obj = {"ts": ts, "msg": msg}
    if metric is not MISSING:
        obj["metric"] = metric
    line = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
    if invalid_escape is not None:
        marker, replacement = invalid_escape
        assert marker in line
        line = line.replace(marker, replacement, 1)
    return line


def run_case(lines, records, label):
    input_bytes = ("\n".join(lines) + "\n").encode("utf-8")
    proc = subprocess.run(
        ["python3", AGENT_PATH],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert proc.returncode == 0, (
        f"{label}: detector exited with {proc.returncode}\n"
        f"stderr: {proc.stderr.decode('utf-8', errors='replace')}"
    )
    expected = expected_output(records)
    assert proc.stdout == expected, (
        f"{label}: output mismatch\n"
        f"input:\n{input_bytes.decode('utf-8', errors='replace')}\n"
        f"expected:\n{expected.decode('utf-8', errors='replace')}\n"
        f"actual:\n{proc.stdout.decode('utf-8', errors='replace')}"
    )


def fixed_case():
    specs = [
        (1, None, "leading null"),
        (2, MISSING, "still null"),
        (3, 1.0, "first, value"),
        (4, None, "forward fill"),
        (5, 3.0, "quote: \"ok\""),
        (6, 5.0, "café"),
        (7, 7.0, "backslash \\ and comma, here"),
        (8, 100.0, "bad __BAD1__ escape"),
        (9, MISSING, "bad __BAD2__ escape"),
        (10, -4.25, "valid A escape"),
    ]
    lines = []
    records = []
    for ts, metric, msg in specs:
        clean = msg
        invalid = None
        if "__BAD1__" in msg:
            invalid = ("__BAD1__", "\\uZZZZ")
            clean = msg.replace("__BAD1__", "?")
        elif "__BAD2__" in msg:
            invalid = ("__BAD2__", "\\u12G4")
            clean = msg.replace("__BAD2__", "?")
        elif msg == "valid A escape":
            line = encode_line(ts, metric, msg).replace("valid A", "valid \\u0041", 1)
            lines.append(line)
            records.append((ts, None if metric is MISSING else metric, msg))
            continue
        lines.append(encode_line(ts, metric, msg, invalid))
        records.append((ts, None if metric is MISSING else metric, clean))
    run_case(lines, records, "fixed semantics")


def random_case(seed):
    rng = random.Random(seed)
    lines = []
    records = []
    ts = rng.randint(-100, 100)
    alphabet = "abcXYZ019 ,quote\" slash\\ café Ω!"
    for i in range(rng.randint(35, 90)):
        ts += rng.randint(1, 8)
        choice = rng.random()
        if choice < 0.12:
            metric = MISSING
        elif choice < 0.28:
            metric = None
        else:
            metric = rng.randint(-400, 400) / 4.0

        msg = "".join(rng.choice(alphabet) for _ in range(rng.randint(0, 28)))
        invalid = None
        clean = msg
        if rng.random() < 0.2:
            marker = f"__BAD_{i}__"
            msg += marker
            bad = rng.choice(["\\uZZZZ", "\\u0X12", "\\u12-4"])
            invalid = (marker, bad)
            clean = msg.replace(marker, "?")

        lines.append(encode_line(ts, metric, msg, invalid))
        records.append((ts, None if metric is MISSING else metric, clean))
    run_case(lines, records, f"random seed {seed}")


def main():
    assert os.path.exists(ORACLE_PATH), "legacy detector path is missing"
    assert os.path.isfile(AGENT_PATH), "detector.py was not created as a file"
    assert os.path.getsize(AGENT_PATH) > 0, "detector.py is empty"

    fixed_case()
    base = int.from_bytes(secrets.token_bytes(8), "big")
    for offset in range(12):
        random_case(base + offset)


if __name__ == "__main__":
    main()
PY

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
