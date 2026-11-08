#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import random
import sqlite3
import subprocess
import tempfile
import pytest


def test_recovered_database():
    sql_path = "/home/user/recovered.sql"
    assert os.path.exists(sql_path), f"Missing recovered SQL dump at {sql_path}"
    assert os.path.isfile(sql_path), f"Recovered SQL dump is not a regular file: {sql_path}"

    with open(sql_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "audio_metadata" in content, "Recovered SQL does not contain 'audio_metadata' table."
    assert "0.005" in content, "Recovered SQL does not contain the expected threshold value (0.005)."

    # Verify that this is a usable SQL dump containing the actual recovered schema and row,
    # rather than a text file containing only the expected strings.
    conn = sqlite3.connect(":memory:")
    try:
        conn.executescript(content)
        columns = conn.execute("PRAGMA table_info(audio_metadata)").fetchall()
        assert [(row[1], row[2].upper()) for row in columns] == [
            ("id", "INTEGER"),
            ("threshold", "REAL"),
        ], f"Incorrect recovered audio_metadata schema: {columns}"

        rows = conn.execute(
            "SELECT id, threshold FROM audio_metadata ORDER BY id"
        ).fetchall()
        assert len(rows) == 1, f"Incorrect recovered records: {rows}"
        assert rows[0][0] == 1, f"Incorrect recovered metadata id: {rows[0][0]}"
        assert abs(float(rows[0][1]) - 0.005) < 1e-15, (
            f"Incorrect recovered threshold: {rows[0][1]}"
        )
    finally:
        conn.close()


def test_fuzz_equivalence():
    agent_script = "/home/user/recreated_processor.sh"
    oracle_binary = "/tests/oracle_processor"

    assert os.path.exists(agent_script), f"Agent script missing at {agent_script}"
    assert os.path.isfile(agent_script), f"Agent script is not a regular file: {agent_script}"
    assert os.path.exists(oracle_binary), f"Oracle binary missing at {oracle_binary}"

    # The reference is uploaded only at verification time. Reject a verbatim reference copy.
    assert not filecmp.cmp(agent_script, oracle_binary, shallow=False), (
        "Agent script is byte-identical to the reference implementation"
    )

    random.seed(42)

    for _ in range(1000):
        freq = random.uniform(100.0, 5000.0)
        threshold = random.uniform(0.0001, 10.0)

        # Randomly format inputs to include normal floats, scientific notation, and extra spaces.
        fmt_choice_freq = random.choice([0, 1, 2])
        if fmt_choice_freq == 0:
            freq_str = f"{freq:.4f}"
        elif fmt_choice_freq == 1:
            freq_str = f"{freq:.4e}"
        else:
            freq_str = f"  {freq:.4f}  "

        fmt_choice_thresh = random.choice([0, 1, 2])
        if fmt_choice_thresh == 0:
            thresh_str = f"{threshold:.4f}"
        elif fmt_choice_thresh == 1:
            thresh_str = f"{threshold:.4e}"
        else:
            thresh_str = f"  {threshold:.4f}  "

        try:
            oracle_out = subprocess.check_output(
                ["bash", oracle_binary, freq_str, thresh_str],
                text=True,
                timeout=5,
            ).strip()
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            pytest.fail(f"Oracle failed on inputs '{freq_str}', '{thresh_str}': {e}")

        try:
            agent_out = subprocess.check_output(
                ["bash", agent_script, freq_str, thresh_str],
                text=True,
                timeout=5,
            ).strip()
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            pytest.fail(f"Agent script failed on inputs '{freq_str}', '{thresh_str}': {e}")

        assert oracle_out == agent_out, (
            f"Mismatch on inputs freq='{freq_str}', threshold='{thresh_str}'. "
            f"Oracle: '{oracle_out}', Agent: '{agent_out}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
