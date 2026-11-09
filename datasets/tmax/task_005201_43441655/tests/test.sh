#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import concurrent.futures
from datetime import datetime
import pytest

try:
    import zoneinfo
except ImportError:
    from backports import zoneinfo

def generate_inputs(n=5000):
    random.seed(42)
    timezones = [
        "America/New_York", "Europe/London", "UTC",
        "America/Los_Angeles", "Asia/Tokyo", "Europe/Paris",
        "Australia/Sydney", "America/Chicago"
    ]
    inputs = []

    # 90% valid-ish inputs
    for _ in range(int(n * 0.9)):
        tz_name = random.choice(timezones)
        epoch = random.uniform(1000000000, 2000000000)
        try:
            tz = zoneinfo.ZoneInfo(tz_name)
            dt = datetime.fromtimestamp(epoch, tz)
            ts_str = f"{dt.strftime('%Y-%m-%dT%H:%M:%S.%f')} {tz_name}"
            inputs.append(ts_str)
        except Exception:
            # Fallback for any timezone issues
            inputs.append(f"2023-11-05T01:30:00.123456 {tz_name}")

    # 10% malformed inputs
    malformed = [
        "2023-11-05T01:30:00 America/New_York",
        "2023-11-05T01:30:00.123456 Invalid/Timezone",
        "random garbage text",
        "",
        "2023-11-05 01:30:00.123456 UTC",
        "2023-13-05T01:30:00.123456 UTC"
    ]
    while len(inputs) < n:
        inputs.append(random.choice(malformed))

    random.shuffle(inputs)
    return inputs

def run_cmd(cmd, input_arg):
    try:
        result = subprocess.run(
            cmd + [input_arg],
            capture_output=True,
            text=True,
            timeout=2
        )
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return "TIMEOUT"
    except Exception as e:
        return f"ERROR: {str(e)}"

def test_fixed_parser_fuzz_equivalence():
    agent_script = "/home/user/fixed_parser.py"
    oracle_bin = "/tests/oracle"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.isfile(oracle_bin), f"Oracle binary not found at {oracle_bin}"
    assert os.access(oracle_bin, os.X_OK), f"Oracle binary {oracle_bin} is not executable"

    inputs = generate_inputs(5000)

    # Run in parallel to speed up the 5000 executions
    def check_input(inp):
        oracle_out = run_cmd([oracle_bin], inp)
        agent_out = run_cmd(["python3", agent_script], inp)
        return inp, oracle_out, agent_out

    mismatches = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        futures = [executor.submit(check_input, inp) for inp in inputs]
        for future in concurrent.futures.as_completed(futures):
            inp, oracle_out, agent_out = future.result()
            if oracle_out != agent_out:
                mismatches.append((inp, oracle_out, agent_out))
                if len(mismatches) >= 5:
                    break  # Stop early if we have enough failures to report

    if mismatches:
        error_msg = "Output mismatch between oracle and agent script.\n"
        for inp, oracle_out, agent_out in mismatches:
            error_msg += f"Input: {inp!r}\nOracle: {oracle_out!r}\nAgent : {agent_out!r}\n\n"
        pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
