#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import pytest

SCRIPT_PATH = "/home/user/app/find_stable_step.sh"
SIMULATOR_PATH = "/home/user/app/simulate_ode.sh"
LOG_PATH = "/home/user/app/stability_log.txt"


def run_finder(timeout=15):
    return subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user/app",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


def parse_log():
    with open(LOG_PATH, "r") as f:
        content = f.read().strip()

    # Preserve the original format check.
    match = re.search(r"Stable h:\s*([0-9.]+),\s*Max Val:\s*([0-9.]+)", content)
    assert match is not None, (
        f"Log file content '{content}' does not match the required format "
        "'Stable h: <found_h>, Max Val: <max_absolute_value>'."
    )
    assert re.fullmatch(
        r"Stable h:\s*[0-9.]+,\s*Max Val:\s*[0-9.]+", content
    ), f"Log file contains extra or malformed content: {content!r}"
    return content, float(match.group(1)), float(match.group(2))


def test_find_stable_step_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_simulator_exists_and_executable():
    assert os.path.isfile(SIMULATOR_PATH), f"Simulator {SIMULATOR_PATH} does not exist."
    assert os.access(SIMULATOR_PATH, os.X_OK), f"Simulator {SIMULATOR_PATH} is not executable."


def test_run_finder_and_real_log_content():
    if os.path.exists(LOG_PATH):
        os.remove(LOG_PATH)

    result = run_finder()
    assert result.returncode == 0, (
        f"find_stable_step.sh failed with code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist after running the script."

    _, found_h, max_val = parse_log()

    # Preserve the original value assertions.
    assert abs(found_h - 0.0125) < 1e-6, f"Expected stable h to be 0.0125, but found {found_h}."
    assert abs(max_val - 1.0) < 1e-2, f"Expected max value to be around 1.0, but found {max_val}."


def test_adaptation_runs_simulator_and_halves_until_strictly_stable():
    with open(SIMULATOR_PATH, "rb") as f:
        original_simulator = f.read()
    original_mode = stat.S_IMODE(os.stat(SIMULATOR_PATH).st_mode)
    with open(LOG_PATH, "rb") as f:
        original_log = f.read()

    calls_path = "/tmp/stability_simulator_calls.txt"
    if os.path.exists(calls_path):
        os.remove(calls_path)

    controlled_simulator = r'''#!/bin/bash
h=${1-}
printf '%s\n' "$h" >> /tmp/stability_simulator_calls.txt
awk -v h="$h" 'BEGIN {
    d = h - 0.1; if (d < 0) d = -d;
    if (d < 0.000000001) { print "0.0 101.0"; exit }
    d = h - 0.05; if (d < 0) d = -d;
    if (d < 0.000000001) { print "0.0 -100.0"; exit }
    d = h - 0.025; if (d < 0) d = -d;
    if (d < 0.000000001) { print "0.0 100.0"; exit }
    d = h - 0.0125; if (d < 0) d = -d;
    if (d < 0.000000001) { print "0.0 -99.0"; print "1.0 2.0"; exit }
    print "0.0 1000.0"
}'
'''

    try:
        with open(SIMULATOR_PATH, "w") as f:
            f.write(controlled_simulator)
        os.chmod(SIMULATOR_PATH, 0o755)
        if os.path.exists(LOG_PATH):
            os.remove(LOG_PATH)

        result = run_finder()
        assert result.returncode == 0, (
            f"Script failed against controlled simulator. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert os.path.isfile(calls_path), "The adaptation script never invoked simulate_ode.sh."

        with open(calls_path) as f:
            raw_calls = [line.strip() for line in f if line.strip()]
        try:
            calls = [float(value) for value in raw_calls]
        except ValueError as exc:
            pytest.fail(f"Simulator was called with a non-numeric step size: {raw_calls!r}: {exc}")

        expected = [0.1, 0.05, 0.025, 0.0125]
        assert len(calls) == len(expected), (
            f"Expected exactly the halving sequence {expected}, but simulator calls were {raw_calls}."
        )
        assert all(abs(actual - wanted) < 1e-9 for actual, wanted in zip(calls, expected)), (
            f"Expected halving sequence {expected}, but simulator calls were {raw_calls}."
        )

        assert os.path.isfile(LOG_PATH), "Script did not create stability_log.txt after finding stability."
        _, found_h, max_val = parse_log()
        assert abs(found_h - 0.0125) < 1e-9, f"Controlled run reported the wrong h: {found_h}."
        assert abs(max_val - 99.0) < 1e-9, (
            f"Controlled run should report maximum absolute value 99.0, but reported {max_val}."
        )
    finally:
        with open(SIMULATOR_PATH, "wb") as f:
            f.write(original_simulator)
        os.chmod(SIMULATOR_PATH, original_mode)
        with open(LOG_PATH, "wb") as f:
            f.write(original_log)


def test_stability_log_exists():
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} does not exist."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
