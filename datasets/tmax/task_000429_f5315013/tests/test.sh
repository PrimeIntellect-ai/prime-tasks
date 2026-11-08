#!/bin/bash
set -u
mkdir -p /logs/verifier
passed=1

# Require an actual, non-symlinked Go source file.
if ! python3 - <<'PY'
import os
import stat
p = "/home/user/audit.go"
st = os.lstat(p)
assert stat.S_ISREG(st.st_mode), f"{p} is not a regular file"
assert not os.path.islink(p), f"{p} must not be a symlink"
PY
then
    passed=0
fi

BIN="$(mktemp /tmp/audit_submission.XXXXXX)"
rm -f "$BIN"
if [ "$passed" -eq 1 ]; then
    if ! go build -o "$BIN" /home/user/audit.go; then
        passed=0
    fi
fi

# Exercise the compiled program against randomized encoded tokens and profile
# permissions so a hardcoded copy of the expected CSV cannot pass.
if [ -x "$BIN" ]; then
    if ! AUDIT_BIN="$BIN" python3 - <<'PY'
import base64
import csv
import json
import os
import random
import secrets
import shutil
import subprocess

home = "/home/user"
auth = os.path.join(home, "auth_dump.txt")
profiles = os.path.join(home, "profiles")
report = os.path.join(home, "escalation_audit.csv")
tag = secrets.token_hex(8)
backup_auth = f"/tmp/auth_dump_backup_{tag}"
backup_profiles = f"/tmp/profiles_backup_{tag}"

names = [f"user_{secrets.token_hex(5)}" for _ in range(7)]
random.SystemRandom().shuffle(names)
base_uid = secrets.randbelow(40000) + 2000
records = [
    {"user": names[0], "role": "admin", "uid": base_uid + 1, "mode": 0o666},
    {"user": names[1], "role": "admin", "uid": base_uid + 2, "mode": 0o640},
    {"user": names[2], "role": "admin", "uid": base_uid + 3, "mode": 0o602},
    {"user": names[3], "role": "admin", "uid": 0,            "mode": 0o666},
    {"user": names[4], "role": "user",  "uid": base_uid + 4, "mode": 0o666},
    {"user": names[5], "role": "viewer","uid": base_uid + 5, "mode": 0o777},
    {"user": names[6], "role": "user",  "uid": base_uid + 6, "mode": 0o600},
]
random.SystemRandom().shuffle(records)

def encode(payload):
    raw = json.dumps(
        {"user": payload["user"], "role": payload["role"], "uid": payload["uid"]},
        separators=(",", ":"),
    ).encode("utf-8")
    return base64.b64encode(bytes(b ^ 0x5A for b in raw)).decode("ascii")

os.rename(auth, backup_auth)
os.rename(profiles, backup_profiles)
try:
    os.mkdir(profiles, 0o755)
    with open(auth, "w", encoding="utf-8") as f:
        for record in records:
            f.write(encode(record) + "\n")

    for record in records:
        path = os.path.join(profiles, record["user"] + ".json")
        with open(path, "w", encoding="utf-8") as f:
            f.write("{}\n")
        os.chmod(path, record["mode"])

    if os.path.lexists(report):
        os.unlink(report)

    result = subprocess.run(
        [os.environ["AUDIT_BIN"]],
        cwd=home,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"compiled audit program exited with {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(report), "compiled audit program did not create the CSV"

    expected = [["Username", "UID", "WorldWritable"]]
    anomalous = [r for r in records if r["role"] == "admin" and r["uid"] > 0]
    for record in sorted(anomalous, key=lambda r: r["user"]):
        expected.append([
            record["user"],
            str(record["uid"]),
            "true" if record["mode"] & 0o002 else "false",
        ])

    with open(report, newline="", encoding="utf-8") as f:
        actual = list(csv.reader(f))
    assert actual == expected, f"randomized audit output was incorrect: {actual!r}"
finally:
    if os.path.lexists(auth):
        os.unlink(auth)
    if os.path.lexists(profiles):
        if os.path.isdir(profiles) and not os.path.islink(profiles):
            shutil.rmtree(profiles)
        else:
            os.unlink(profiles)
    os.rename(backup_auth, auth)
    os.rename(backup_profiles, profiles)
PY
    then
        passed=0
    fi

    # Re-run the submitted artifact on the original supplied data before retaining
    # the original verifier's exact report assertions.
    rm -f /home/user/escalation_audit.csv
    if ! (cd /home/user && "$BIN"); then
        passed=0
    fi
else
    passed=0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_escalation_audit_csv_exists():
    csv_path = "/home/user/escalation_audit.csv"
    assert os.path.isfile(csv_path), f"The audit report {csv_path} does not exist."

def test_escalation_audit_csv_content():
    csv_path = "/home/user/escalation_audit.csv"
    assert os.path.isfile(csv_path), f"The audit report {csv_path} does not exist."

    with open(csv_path, "r") as f:
        content = f.read().strip().splitlines()

    expected_content = [
        "Username,UID,WorldWritable",
        "bob,1002,true",
        "dave,1004,true",
        "eve,1005,false"
    ]

    assert len(content) > 0, "The CSV file is empty."
    assert content[0] == expected_content[0], f"CSV header is incorrect. Expected '{expected_content[0]}', got '{content[0]}'."

    # Check if lines match exactly
    assert len(content) == len(expected_content), f"Expected {len(expected_content)} lines, but got {len(content)}."

    for i in range(1, len(expected_content)):
        assert content[i] == expected_content[i], f"Line {i+1} is incorrect. Expected '{expected_content[i]}', got '{content[i]}'."
TEST_EOF

if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    passed=0
fi

rm -f "$BIN"
if [ "$passed" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
