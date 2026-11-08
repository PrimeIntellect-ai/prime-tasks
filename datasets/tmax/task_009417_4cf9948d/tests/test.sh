#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import subprocess
import tempfile
from pathlib import Path


def test_regression_script():
    regression_script = '/home/user/regression.sh'
    assert os.path.exists(regression_script), f"{regression_script} does not exist."
    assert os.access(regression_script, os.X_OK), f"{regression_script} is not executable."

    result = subprocess.run([regression_script], capture_output=True, text=True)
    assert "PASS" in result.stdout, f"Expected 'PASS' in output of {regression_script}, got: {result.stdout}"


def test_skipped_log():
    skipped_log = '/home/user/skipped.log'
    assert os.path.exists(skipped_log), f"{skipped_log} was not created."

    with open(skipped_log, 'r') as f:
        content = f.read().strip()

    expected_content = "SKIPPED: 30,20,50"
    assert expected_content in content, f"Expected '{expected_content}' in {skipped_log}, got: '{content}'"

    # Ensure no other rows were skipped incorrectly
    lines = [line for line in content.split('\n') if line.strip()]
    assert len(lines) == 1, f"Expected exactly 1 skipped row in {skipped_log}, but found {len(lines)}"


def test_calculate_risk_script_success():
    script_path = '/home/user/calculate_risk.sh'
    assert os.path.exists(script_path), f"{script_path} is missing."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."

    # Remove skipped.log to ensure the script regenerates it properly
    if os.path.exists('/home/user/skipped.log'):
        os.remove('/home/user/skipped.log')

    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"{script_path} failed with exit code {result.returncode}. Stderr: {result.stderr}"

    # Verify skipped log was regenerated correctly
    skipped_log = '/home/user/skipped.log'
    assert os.path.exists(skipped_log), f"{skipped_log} was not created after running {script_path}."
    with open(skipped_log, 'r') as f:
        content = f.read().strip()
    assert "SKIPPED: 30,20,50" in content, f"Validation logic in {script_path} failed to skip the correct row."


def test_regression_script_actually_runs_and_checks_calculate_risk():
    regression = Path('/home/user/regression.sh')
    calculate = Path('/home/user/calculate_risk.sh')
    backup = Path(tempfile.mktemp(prefix='calculate_risk_backup_', dir='/tmp'))
    marker = Path(tempfile.mktemp(prefix='calculate_risk_called_', dir='/tmp'))

    os.replace(calculate, backup)
    try:
        calculate.write_text(f"#!/bin/bash\necho called > {marker}\nexit 0\n")
        calculate.chmod(0o755)
        result = subprocess.run([str(regression)], capture_output=True, text=True)
        assert marker.exists(), "regression.sh did not run /home/user/calculate_risk.sh"
        assert result.returncode == 0, "regression.sh did not succeed when calculate_risk.sh exited 0"
        assert "PASS" in result.stdout, "regression.sh did not print PASS for a successful run"

        marker.unlink(missing_ok=True)
        calculate.write_text(f"#!/bin/bash\necho called > {marker}\nexit 37\n")
        calculate.chmod(0o755)
        result = subprocess.run([str(regression)], capture_output=True, text=True)
        assert marker.exists(), "regression.sh did not run the failing calculate_risk.sh probe"
        assert result.returncode != 0, "regression.sh returned success when calculate_risk.sh failed"
        assert "FAIL" in result.stdout, "regression.sh did not print FAIL when calculate_risk.sh failed"
        assert "PASS" not in result.stdout, "regression.sh printed PASS when calculate_risk.sh failed"
    finally:
        calculate.unlink(missing_ok=True)
        os.replace(backup, calculate)
        marker.unlink(missing_ok=True)


def test_general_crash_condition_and_helper_invocations():
    calculate = Path('/home/user/calculate_risk.sh')
    data = Path('/home/user/data.csv')
    helper = Path('/home/user/math_helper')
    skipped = Path('/home/user/skipped.log')

    original_data = data.read_bytes()
    helper_backup = Path(tempfile.mktemp(prefix='math_helper_backup_', dir='/tmp'))
    call_log = Path(tempfile.mktemp(prefix='math_helper_calls_', dir='/tmp'))

    rng = random.SystemRandom()
    rows = []
    for _ in range(9):
        a = rng.randint(-500, 500)
        b = rng.randint(-500, 500)
        rows.append((a, b, a + b, True))
    for _ in range(11):
        a = rng.randint(-500, 500)
        b = rng.randint(-500, 500)
        c = rng.randint(-1000, 1000)
        while c == a + b:
            c = rng.randint(-1000, 1000)
        rows.append((a, b, c, False))
    rng.shuffle(rows)

    expected_skipped = [f"SKIPPED: {a},{b},{c}" for a, b, c, crashes in rows if crashes]
    expected_calls = [f"{a},{b},{c}" for a, b, c, crashes in rows if not crashes]

    os.replace(helper, helper_backup)
    try:
        helper.write_text(
            "#!/bin/bash\n"
            f"printf '%s,%s,%s\\n' \"$1\" \"$2\" \"$3\" >> {call_log}\n"
            "printf '0\\n'\n"
            "exit 0\n"
        )
        helper.chmod(0o755)

        csv = "A,B,C\n" + "".join(f"{a},{b},{c}\n" for a, b, c, _ in rows)
        data.write_text(csv)
        skipped.unlink(missing_ok=True)
        call_log.unlink(missing_ok=True)

        result = subprocess.run([str(calculate)], capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, (
            f"calculate_risk.sh failed on generated inputs with exit code {result.returncode}. "
            f"Stdout: {result.stdout} Stderr: {result.stderr}"
        )

        assert skipped.exists(), "calculate_risk.sh did not create skipped.log for generated crash rows"
        actual_skipped = [line.strip() for line in skipped.read_text().splitlines() if line.strip()]
        assert actual_skipped == expected_skipped, (
            "Rows satisfying A + B = C were not skipped exactly as required. "
            f"Expected {expected_skipped}, got {actual_skipped}"
        )

        actual_calls = []
        if call_log.exists():
            actual_calls = [line.strip() for line in call_log.read_text().splitlines() if line.strip()]
        assert actual_calls == expected_calls, (
            "calculate_risk.sh must call math_helper once for every valid row, in order, and never "
            f"for rows where A + B = C. Expected {expected_calls}, got {actual_calls}"
        )
    finally:
        data.write_bytes(original_data)
        helper.unlink(missing_ok=True)
        os.replace(helper_backup, helper)
        call_log.unlink(missing_ok=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
