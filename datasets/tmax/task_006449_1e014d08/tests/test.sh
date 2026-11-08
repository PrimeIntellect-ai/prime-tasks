#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
import tempfile

SCRIPT_PATH = '/home/user/monitor.py'
PYTHON_BIN = '/home/user/venv/bin/python'
REPORT_PATH = '/home/user/report.json'
FIXTURE_PATH = '/home/user/uptime_data.json'


def read_report():
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} does not exist. Did you run the script?"
    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {REPORT_PATH} is not valid JSON."
    assert "max_downtime_minutes" in data, "Key 'max_downtime_minutes' is missing in report.json."
    return data


def expected_max_downtime(statuses):
    best = 0
    current = 0
    for status in statuses:
        if status == 'DOWN':
            current += 1
            best = max(best, current)
        else:
            current = 0
    return best


def run_monitor(data_path):
    env = os.environ.copy()
    env['UPTIME_DATA_PATH'] = data_path
    result = subprocess.run(
        [PYTHON_BIN, SCRIPT_PATH],
        env=env,
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        "Script failed to execute. This could be due to unresolved dependency conflicts "
        f"or syntax errors. stderr:\n{result.stderr}"
    )


def test_final_state_and_behavior():
    # Preserve the original final-state assertions.
    data = read_report()
    expected_downtime = 4
    actual_downtime = data["max_downtime_minutes"]
    assert actual_downtime == expected_downtime, (
        f"Expected max_downtime_minutes to be {expected_downtime}, "
        f"but got {actual_downtime}. The algorithmic bug might not be fully fixed."
    )

    assert os.path.exists(PYTHON_BIN), f"Python binary missing at {PYTHON_BIN}"
    assert os.path.exists(SCRIPT_PATH), f"Monitor script missing at {SCRIPT_PATH}"
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"Monitor script is not a regular file: {SCRIPT_PATH}"

    # Confirm the virtual environment has no broken declared dependencies and
    # that the imports required by monitor.py work in that environment.
    check = subprocess.run(
        [PYTHON_BIN, '-m', 'pip', 'check'], capture_output=True, text=True, timeout=20
    )
    assert check.returncode == 0, f"Virtual environment has broken dependencies:\n{check.stdout}{check.stderr}"
    imports = subprocess.run(
        [PYTHON_BIN, '-c', 'import requests, urllib3'], capture_output=True, text=True, timeout=20
    )
    assert imports.returncode == 0, f"Required packages cannot be imported:\n{imports.stderr}"

    # Exercise the actual script with verifier-generated inputs. The cases vary
    # on every run and include trailing streaks, interior streaks, and no streak.
    rng = secrets.SystemRandom()
    cases = [
        ['UP'] * rng.randint(1, 5),
        ['DOWN'] * rng.randint(2, 9),
        ['UP'] * rng.randint(1, 4) + ['DOWN'] * rng.randint(2, 7),
    ]
    for _ in range(7):
        length = rng.randint(8, 40)
        cases.append([rng.choice(('UP', 'DOWN')) for _ in range(length)])

    with tempfile.TemporaryDirectory(prefix='uptime-verifier-') as tmpdir:
        for index, statuses in enumerate(cases):
            input_path = os.path.join(tmpdir, f'input-{index}-{secrets.token_hex(6)}.json')
            with open(input_path, 'w') as f:
                json.dump({'statuses': statuses}, f)
            if os.path.exists(REPORT_PATH):
                os.remove(REPORT_PATH)
            run_monitor(input_path)
            generated = read_report()
            expected = expected_max_downtime(statuses)
            assert generated['max_downtime_minutes'] == expected, (
                f"For statuses {statuses!r}, expected {expected} but got "
                f"{generated['max_downtime_minutes']!r}."
            )

    # Preserve the original fixed-fixture execution check and leave the required
    # final report corresponding to the instructed data source.
    run_monitor(FIXTURE_PATH)
    final_data = read_report()
    assert final_data['max_downtime_minutes'] == 4, (
        f"Expected max_downtime_minutes to be 4, but got {final_data['max_downtime_minutes']}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
