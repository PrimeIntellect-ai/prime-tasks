#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_bug_report_exists_and_correct():
    """Check if the bug report exists and contains the correctly identified anomaly."""
    report_path = '/home/user/bug_report.txt'
    assert os.path.isfile(report_path), f"File {report_path} is missing. The task requires creating this file."

    # Recompute the expected value from the logs directly
    logs = []
    log_files = {
        'alpha': '/home/user/logs/alpha.log', 
        'beta': '/home/user/logs/beta.log', 
        'gamma': '/home/user/logs/gamma.log'
    }

    for svc, path in log_files.items():
        assert os.path.isfile(path), f"Expected log file {path} is missing."
        with open(path, 'r') as f:
            for line in f:
                if 'SIM-9942' in line:
                    # Parse format: [YYYY-MM-DDTHH:MM:SS.mmmZ] [TxID] [ACTION] State:v1,v2,v3,v4,...
                    parts = line.strip().split(' ')
                    if len(parts) >= 4:
                        timestamp = parts[0].strip('[]')
                        state_str = parts[3].split('State:')[1]
                        state = list(map(int, state_str.split(',')))
                        energy = sum(state)
                        logs.append((timestamp, svc, energy))

    # Sort chronologically by timestamp
    logs.sort(key=lambda x: x[0])

    assert len(logs) > 0, "No logs found for SIM-9942 to test against."

    initial_energy = logs[0][2]
    expected_line = None

    # Find the first anomaly
    for timestamp, svc, energy in logs:
        if energy != initial_energy:
            expected_line = f"{timestamp},{svc},{initial_energy},{energy}"
            break

    assert expected_line is not None, "No energy anomaly found in the logs for SIM-9942."

    # Verify the user's output
    with open(report_path, 'r') as f:
        content = f.read().strip()

    assert content == expected_line, (
        f"Content of {report_path} is incorrect.\n"
        f"Expected: '{expected_line}'\n"
        f"Actual:   '{content}'"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
