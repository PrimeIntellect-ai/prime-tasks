#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import subprocess


def valid_wal_lines(raw_text):
    valid = []
    for line in raw_text.splitlines():
        parts = line.split('|')
        if len(parts) != 5:
            continue
        seq, action, key, val, chk = parts
        if not seq.isdigit() or not chk.isdigit():
            continue
        expected_chk = len((key + val).encode('utf-8'))
        if int(chk) != expected_chk:
            continue
        valid.append(line)
    return valid


def test_wal_recovered_log():
    recover_path = "/home/user/recover.sh"
    wal_path = "/home/user/wal.log"
    wal_recovered_path = "/home/user/wal_recovered.log"

    assert os.path.isfile(recover_path), f"Expected {recover_path} to exist."
    assert os.path.isfile(wal_path), f"Expected {wal_path} to exist."

    with open(wal_path, "rb") as f:
        original_wal_bytes = f.read()
    original_wal_text = original_wal_bytes.decode("utf-8")
    expected_lines = valid_wal_lines(original_wal_text)

    if os.path.lexists(wal_recovered_path):
        os.remove(wal_recovered_path)

    result = subprocess.run(
        ["bash", recover_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"recover.sh exited with {result.returncode}. stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )

    with open(wal_path, "rb") as f:
        assert f.read() == original_wal_bytes, "recover.sh must not modify wal.log."

    assert os.path.isfile(wal_recovered_path), f"Expected {wal_recovered_path} to exist."

    with open(wal_recovered_path, "r") as f:
        lines = f.read().splitlines()

    assert len(lines) == 497, f"Expected exactly 497 valid lines in wal_recovered.log, found {len(lines)}."

    for line in lines:
        parts = line.split('|')
        assert len(parts) == 5, f"Line does not have exactly 5 fields: {line}"
        seq, action, key, val, chk = parts

        expected_chk = len(key) + len(val)
        assert chk.isdigit() and int(chk) == expected_chk, f"Invalid checksum for line: {line}. Expected {expected_chk}, got {chk}."

    assert lines == expected_lines, (
        "wal_recovered.log must contain exactly the valid lines from wal.log, "
        "in their original order."
    )


def test_apply_wal_sh_fixed():
    script_path = "/home/user/apply_wal.sh"
    recovered_path = "/home/user/wal_recovered.log"
    assert os.path.isfile(script_path), f"Expected {script_path} to exist."

    with open(script_path, "r") as f:
        content = f.read()

    # The original buggy script contained: if [ "$seq" -ge "$MAX_SEQ" ]; then
    # The fix should replace -ge with -gt or equivalent logic.
    assert not re.search(r'"\$seq"\s+-ge\s+"\$MAX_SEQ"', content), "The boundary bug (-ge) is still present in apply_wal.sh."
    assert not re.search(r'\$seq\s+-ge\s+\$MAX_SEQ', content), "The boundary bug (-ge) is still present in apply_wal.sh."

    # Check for presence of a likely fix (-gt, >)
    has_fix = bool(re.search(r'-gt|>', content))
    assert has_fix, "Could not find a valid fix (like -gt or >) for the boundary condition in apply_wal.sh."

    assert os.path.isfile(recovered_path), f"Expected {recovered_path} to exist."
    with open(recovered_path, "rb") as f:
        recovered_bytes = f.read()

    controlled_wal = (
        "1|SET|safe|ok|6\n"
        "7|SET|trip|CRASH_TRIGGER_992|21\n"
        "9|SET|later|ok|7\n"
    )

    try:
        with open(recovered_path, "w") as f:
            f.write(controlled_wal)

        before = subprocess.run(
            ["bash", script_path, "6"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert before.returncode == 0, (
            "apply_wal.sh should succeed when the poison transaction is beyond the target."
        )

        exact = subprocess.run(
            ["bash", script_path, "7"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert exact.returncode != 0, (
            "apply_wal.sh did not process the transaction whose SEQ exactly equals "
            "the requested target; the boundary is still exclusive."
        )
    finally:
        with open(recovered_path, "wb") as f:
            f.write(recovered_bytes)

    full_run = subprocess.run(
        ["bash", script_path, "99999"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert full_run.returncode != 0, (
        "apply_wal.sh 99999 should encounter the poison transaction in the recovered WAL."
    )


def test_poison_seq_txt():
    poison_path = "/home/user/poison_seq.txt"
    assert os.path.isfile(poison_path), f"Expected {poison_path} to exist."

    with open(poison_path, "r") as f:
        content = f.read().strip()

    assert content == "312", f"Expected poison_seq.txt to contain exactly '312', but found '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
