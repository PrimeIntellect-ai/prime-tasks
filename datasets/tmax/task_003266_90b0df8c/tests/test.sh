#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import string
import pytest

ORACLE_PATH = "/app/db_recover"
AGENT_PATH = "/home/user/recover.py"
NUM_ITERATIONS = 500


def generate_random_input(seed):
    random.seed(seed)
    num_lines = random.randint(10, 100)
    lines = []

    for _ in range(num_lines):
        tx_id = random.randint(1, 10000)
        local_ts = random.randint(1600000000, 1700000000)

        sign = random.choice(['+', '-'])
        hh = random.randint(0, 14)
        if hh == 14:
            mm = 0
            sign = '+'
        elif hh == 12 and sign == '-':
            mm = 0
        else:
            mm = random.choice([0, 15, 30, 45])

        tz_offset = f"{sign}{hh:02d}{mm:02d}"
        operation = "SET" if random.random() < 0.8 else "DEL"
        key_len = random.randint(2, 5)
        key = ''.join(random.choices(string.ascii_letters + string.digits, k=key_len))
        val_len = random.randint(4, 8)
        value = ''.join(random.choices(string.ascii_letters + string.digits, k=val_len))
        lines.append(f"{tx_id} {local_ts} {tz_offset} {operation} {key} {value}")

    return "\n".join(lines) + "\n"


def offset_seconds(tz):
    sign = 1 if tz[0] == '+' else -1
    return sign * (int(tz[1:3]) * 3600 + int(tz[3:5]) * 60)


def generate_adversarial_input(seed):
    """Generate guaranteed same-key timezone conflicts and equal-UTC ties."""
    rng = random.Random(seed)
    lines = []
    offset_pairs = [
        ('-1200', '+1400'),
        ('-0330', '+0545'),
        ('-0800', '+0930'),
        ('-0400', '+1245'),
    ]

    # For every TZ key, the UTC winner has a smaller local timestamp than the
    # loser. Alternating SET/DEL winners makes the conflict observable even
    # when a flawed implementation suppresses deleted keys.
    for i in range(48):
        key = f"TZ{i:03d}"
        base_utc = 1600000000 + rng.randint(0, 50000000)
        winner_tz, loser_tz = offset_pairs[i % len(offset_pairs)]
        winner_utc = base_utc + 1
        loser_utc = base_utc
        winner_local = winner_utc + offset_seconds(winner_tz)
        loser_local = loser_utc + offset_seconds(loser_tz)
        assert winner_local < loser_local

        if i % 2 == 0:
            winner_op, loser_op = 'SET', 'DEL'
        else:
            winner_op, loser_op = 'DEL', 'SET'

        winner = f"{7000+i} {winner_local} {winner_tz} {winner_op} {key} Win{i}"
        loser = f"{2000+i} {loser_local} {loser_tz} {loser_op} {key} Lose{i}"
        lines.extend([winner, loser] if i % 2 else [loser, winner])

    # Same UTC and same local timestamp: only the larger TxID may win. Both
    # input orders are represented so first-wins and last-wins shortcuts fail.
    for i in range(48):
        key = f"EQ{i:03d}"
        utc = 1650000000 + rng.randint(0, 50000000)
        tz = ['+0000', '+0530', '-0400', '+1245'][i % 4]
        local = utc + offset_seconds(tz)
        low_tx = 100 + i
        high_tx = 9000 + i
        high_op = 'SET' if i % 2 == 0 else 'DEL'
        low_op = 'DEL' if high_op == 'SET' else 'SET'
        low = f"{low_tx} {local} {tz} {low_op} {key} Low{i}"
        high = f"{high_tx} {local} {tz} {high_op} {key} High{i}"
        lines.extend([low, high] if i % 2 == 0 else [high, low])

    # Equal UTC represented by different local timestamps and offsets. This
    # simultaneously checks normalization and the TxID tie-breaker.
    for i in range(32):
        key = f"CT{i:03d}"
        utc = 1680000000 + rng.randint(0, 10000000)
        low_tz = '+1400'
        high_tz = '-1200'
        low = f"{300+i} {utc + offset_seconds(low_tz)} {low_tz} SET {key} LowCross{i}"
        high_op = 'SET' if i % 2 == 0 else 'DEL'
        high = f"{9500+i} {utc + offset_seconds(high_tz)} {high_tz} {high_op} {key} HighCross{i}"
        lines.extend([low, high] if i % 2 == 0 else [high, low])

    return "\n".join(lines) + "\n"


def run_program(cmd, input_data):
    try:
        result = subprocess.run(
            cmd,
            input=input_data,
            text=True,
            capture_output=True,
            check=True,
            timeout=5
        )
        return result.stdout
    except subprocess.CalledProcessError as e:
        return f"ERROR: {e.stderr}"
    except subprocess.TimeoutExpired:
        return "ERROR: Timeout"


def assert_equivalent(input_data, label):
    oracle_output = run_program([ORACLE_PATH], input_data)
    agent_output = run_program(["python3", AGENT_PATH], input_data)
    if oracle_output != agent_output:
        pytest.fail(
            f"Mismatch on {label}!\n\n"
            f"INPUT:\n{input_data}\n"
            f"EXPECTED (Oracle):\n{oracle_output}\n"
            f"ACTUAL (Agent):\n{agent_output}\n"
        )


def test_recover_script_exists():
    assert os.path.exists(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle {ORACLE_PATH} is not executable"

    for i in range(NUM_ITERATIONS):
        input_data = generate_random_input(seed=42 + i)
        assert_equivalent(input_data, f"fuzz iteration {i+1}")


def test_timezone_conflicts_and_txid_ties():
    for seed in (918273, 271828, 314159):
        assert_equivalent(generate_adversarial_input(seed), f"adversarial seed {seed}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
