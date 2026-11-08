#!/bin/bash
set -e
mkdir -p /logs/verifier

OFFICIAL_JQ=/tmp/official-jq-1.6
rm -f "$OFFICIAL_JQ"
if ! /usr/bin/curl -fL --retry 3 --connect-timeout 15 --max-time 120 \
  https://github.com/jqlang/jq/releases/download/jq-1.6/jq-linux64 \
  -o "$OFFICIAL_JQ"; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi
chmod 700 "$OFFICIAL_JQ"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import filecmp
import json
import os
import random
import string
import subprocess
from urllib.parse import parse_qs, urlsplit


def test_jq_installed():
    jq_bin = "/home/user/bin/jq"
    assert os.path.exists(jq_bin), f"{jq_bin} does not exist."
    assert os.path.isfile(jq_bin), f"{jq_bin} is not a file."
    assert os.access(jq_bin, os.X_OK), f"{jq_bin} is not executable."


def test_jq_is_official_1_6_binary():
    jq_bin = "/home/user/bin/jq"
    official = "/tmp/official-jq-1.6"
    assert filecmp.cmp(jq_bin, official, shallow=False), (
        f"{jq_bin} is not the official jq 1.6 Linux 64-bit binary."
    )

    result = subprocess.run(
        [jq_bin, "--version"], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "jq-1.6"


def test_jq_parses_verifier_generated_json():
    jq_bin = "/home/user/bin/jq"
    rng = random.SystemRandom()
    items = []
    expected = []
    for _ in range(8):
        user_id = rng.randrange(1, 10**9)
        action = "".join(rng.choice(string.ascii_letters) for _ in range(18))
        score = rng.randrange(-100000, 100000)
        active = bool(rng.randrange(2))
        items.append({
            "userId": user_id,
            "action": action,
            "score": score,
            "active": active,
        })
        expected.append(
            f"{user_id}|{action}|{score * 2}|{'true' if active else 'false'}"
        )

    result = subprocess.run(
        [
            jq_bin,
            "-r",
            '.items[] | "\\(.userId)|\\(.action)|\\(.score * 2)|\\(.active)"',
        ],
        input=json.dumps({"items": items}),
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout.splitlines() == expected


def test_processed_events_csv():
    output_file = "/home/user/processed_events.csv"
    assert os.path.exists(output_file), f"Output file {output_file} is missing."
    assert os.path.isfile(output_file), f"{output_file} is not a file."

    expected_csv = (
        "userId,action\n"
        "101,login\n"
        "204,purchase\n"
        "99,logout"
    )

    with open(output_file, "r") as f:
        content = f.read().strip()

    assert content == expected_csv, (
        f"Content of {output_file} is incorrect.\n"
        f"Expected:\n{expected_csv}\n"
        f"Got:\n{content}"
    )


def test_log_entries_are_decoded_and_parsed_by_submitted_jq():
    jq_bin = "/home/user/bin/jq"
    rows = []

    with open("/home/user/requests.log", "r", encoding="utf-8") as log_file:
        for raw_line in log_file:
            parts = raw_line.rstrip("\n").split(" ")
            if len(parts) != 3 or parts[0] != "GET" or parts[2] != "HTTP/1.1":
                continue

            parsed = urlsplit(parts[1])
            if parsed.path != "/api/v1/event":
                continue

            values = parse_qs(parsed.query, keep_blank_values=True).get("data", [])
            assert len(values) == 1, "A matching request must have one data parameter."
            decoded = base64.b64decode(values[0], validate=True)
            result = subprocess.run(
                [
                    jq_bin,
                    "-r",
                    '[.userId, .action] | map(tostring) | join(",")',
                ],
                input=decoded,
                capture_output=True,
                timeout=10,
            )
            assert result.returncode == 0, result.stderr.decode("utf-8", "replace")
            rows.append(result.stdout.decode("utf-8").rstrip("\n"))

    derived_csv = "userId,action\n" + "\n".join(rows)
    with open("/home/user/processed_events.csv", "r", encoding="utf-8") as output:
        actual_csv = output.read().strip()
    assert actual_csv == derived_csv
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
