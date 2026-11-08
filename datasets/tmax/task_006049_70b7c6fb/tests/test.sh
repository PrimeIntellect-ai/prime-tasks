#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess
import pytest

APP = "/home/user/app"
RECOVER = f"{APP}/recover.sh"
WAL = f"{APP}/data.wal"
RECOVERED = f"{APP}/recovered.csv"
CURRENT = f"{APP}/current_state.json"
KNOWN_GOOD = f"{APP}/known_good.json"
STATE_DIFF = f"{APP}/state.diff"
TRANSFORM = f"{APP}/transform.sh"

CANONICAL_WAL = """100,ADD,50,150
101,SUB,10,111
102,ADD,20,122
103,ADD,5,TRUNCATED
104,ADD,15,119
105,SUB,5,100
106,MALFORMED,LINE
107,ADD,10,117
"""

CANONICAL_RECOVERED = [
    "100,ADD,50,150",
    "101,SUB,10,111",
    "102,ADD,20,122",
    "104,ADD,15,119",
    "107,ADD,10,117",
]

EXPECTED_TRANSFORM = """#!/bin/bash
total=0
while IFS=, read -r ts op val chk; do
    if [ "$op" == "ADD" ]; then total=$((total + val)); fi
    if [ "$op" == "SUB" ]; then total=$((total - val)); fi
done < "$1"
echo "{\"total\": $total}" > /home/user/app/current_state.json
"""


def remove_path(path):
    if not os.path.lexists(path):
        return
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    else:
        os.unlink(path)


def write_wal(lines):
    with open(WAL, "w", newline="") as f:
        f.write("\n".join(lines) + "\n")


def run_recovery(lines, expected):
    write_wal(lines)
    remove_path(RECOVERED)
    result = subprocess.run(
        ["bash", RECOVER], cwd=APP, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f"recover.sh failed with exit code {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(RECOVERED), "recover.sh did not create recovered.csv"
    with open(RECOVERED, "r") as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected, (
        f"recover.sh produced {actual!r}; expected {expected!r}"
    )


def test_00_execute_recovery_and_pipeline():
    assert os.path.isfile(RECOVER), f"The script {RECOVER} does not exist."
    assert os.path.getsize(RECOVER) > 0, "recover.sh is empty."
    assert os.path.isfile(TRANSFORM), f"The legacy script {TRANSFORM} is missing."
    with open(TRANSFORM, "r") as f:
        assert f.read() == EXPECTED_TRANSFORM, "The provided legacy transform.sh was modified."
    with open(KNOWN_GOOD, "r") as f:
        assert f.read() == '{"total": 60}\n', "known_good.json was modified."

    # Exercise the submitted recovery script on unpredictable WAL contents so
    # precomputed recovered.csv/current_state.json files cannot satisfy the test.
    base = secrets.randbelow(700000) + 200000
    v1 = secrets.randbelow(90) + 10
    v2 = secrets.randbelow(90) + 10
    challenge = [
        f"{base},ADD,{v1},{base + v1}",
        f"{base + 1},SUB,{v2},{base + 1 + v2 + 1}",
        f"{base + 2},SUB,{v2},{base + 2 + v2}",
        f"{base + 3},ADD,{v1},TRUNCATED",
        f"{base + 4},ADD,{v2},{base + 4 + v2},EXTRA",
        f"{base + 5},MALFORMED,LINE",
        f"{base + 6},ADD,{v2},{base + 6 + v2}",
    ]
    expected = [challenge[0], challenge[2], challenge[6]]
    run_recovery(challenge, expected)

    # Restore the task input, execute the submitted recovery script again, then
    # execute the supplied transform and the required unified diff operation.
    run_recovery(CANONICAL_WAL.rstrip("\n").splitlines(), CANONICAL_RECOVERED)

    remove_path(CURRENT)
    transformed = subprocess.run(
        [TRANSFORM, RECOVERED], cwd=APP, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert transformed.returncode == 0, (
        f"transform.sh failed with exit code {transformed.returncode}: {transformed.stderr}"
    )

    remove_path(STATE_DIFF)
    with open(STATE_DIFF, "wb") as output:
        diffed = subprocess.run(
            ["diff", "-u", KNOWN_GOOD, CURRENT],
            stdout=output, stderr=subprocess.PIPE, timeout=10
        )
    assert diffed.returncode == 1, (
        f"diff should report state drift (exit 1), but returned {diffed.returncode}: "
        f"{diffed.stderr.decode(errors='replace')}"
    )


def test_recover_script_exists():
    script_path = "/home/user/app/recover.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."


def test_recovered_csv_content():
    csv_path = "/home/user/app/recovered.csv"
    assert os.path.isfile(csv_path), f"The file {csv_path} does not exist."

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "100,ADD,50,150",
        "101,SUB,10,111",
        "102,ADD,20,122",
        "104,ADD,15,119",
        "107,ADD,10,117"
    ]

    assert lines == expected_lines, f"The content of {csv_path} does not match the expected valid lines."


def test_current_state_json():
    json_path = "/home/user/app/current_state.json"
    assert os.path.isfile(json_path), f"The file {json_path} does not exist."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} does not contain valid JSON.")

    assert data.get("total") == 85, f"Expected total in {json_path} to be 85, but got {data.get('total')}."


def test_state_diff_exists_and_valid():
    diff_path = "/home/user/app/state.diff"
    assert os.path.isfile(diff_path), f"The file {diff_path} does not exist."

    with open(diff_path, "r") as f:
        content = f.read()

    assert "---" in content and "+++" in content, f"{diff_path} does not appear to be a unified diff."
    assert "-{\"total\": 60}" in content or "-{\"total\":60}" in content.replace(" ", ""), f"{diff_path} does not show the removal of the old state."
    assert "+{\"total\": 85}" in content or "+{\"total\":85}" in content.replace(" ", ""), f"{diff_path} does not show the addition of the new state."

    expected = subprocess.run(
        ["diff", "-u", KNOWN_GOOD, CURRENT],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert expected.returncode == 1
    assert content.encode() == expected.stdout, "state.diff is not the actual unified diff of the specified files."
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
