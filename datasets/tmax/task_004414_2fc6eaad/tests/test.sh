#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import math
import os
import re
import shutil
import subprocess
import tempfile
import pytest

TARGET_LOG = "/var/log/services/caching-service/usage.log"
SCRIPT = "/home/user/analyze.sh"
PRED_FILE = "/home/user/prediction.txt"


def regression_prediction(rows):
    xs = [float(x) for x, _ in rows]
    ys = [float(y) for _, y in rows]
    xbar = sum(xs) / len(xs)
    ybar = sum(ys) / len(ys)
    denom = sum((x - xbar) ** 2 for x in xs)
    assert denom != 0
    slope = sum((x - xbar) * (y - ybar) for x, y in zip(xs, ys)) / denom
    intercept = ybar - slope * xbar
    return slope * 100.0 + intercept


def read_single_float(path):
    try:
        text = open(path, "r").read().strip()
        value = float(text)
        assert math.isfinite(value)
        return value
    except (OSError, ValueError, AssertionError):
        return None


def run_analyzer():
    # A sentinel prevents a stale prediction from being accepted as this run's result.
    with open(PRED_FILE, "w") as f:
        f.write("not-a-prediction\n")
    os.chown(PRED_FILE, 1000, 1000)
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "env", "HOME=/home/user", "bash", SCRIPT],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"analyze.sh failed with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )

    values = []
    output = result.stdout.strip()
    if output:
        try:
            value = float(output)
            if math.isfinite(value):
                values.append(value)
        except ValueError:
            pass
    file_value = read_single_float(PRED_FILE)
    if file_value is not None:
        values.append(file_value)
    assert values, "analyze.sh neither printed nor wrote a single finite floating-point prediction"
    return values


def test_ssh_works():
    """Verify that SSH to localhost works without a password prompt."""
    try:
        result = subprocess.run(
            ["ssh", "-q", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no", "localhost", "echo", "OK"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert "OK" in result.stdout.strip(), f"SSH to localhost failed. stdout: '{result.stdout}', stderr: '{result.stderr}'"
    except subprocess.TimeoutExpired:
        pytest.fail("SSH command timed out. Ensure SSH is configured correctly to not prompt for a password.")
    except Exception as e:
        pytest.fail(f"SSH command failed with exception: {e}")


def candidate_logrotate_files():
    files = []
    if os.path.isdir("/etc/logrotate.d"):
        files.extend(
            os.path.join("/etc/logrotate.d", name)
            for name in os.listdir("/etc/logrotate.d")
            if os.path.isfile(os.path.join("/etc/logrotate.d", name))
        )
    if os.path.isfile("/etc/logrotate.conf"):
        files.append("/etc/logrotate.conf")
    return files


def has_valid_target_stanza(path):
    try:
        raw = open(path, "r").read()
    except (OSError, UnicodeDecodeError):
        return False

    # Comments cannot satisfy either the path or the daily directive.
    text = "\n".join(line.split("#", 1)[0] for line in raw.splitlines())
    if text.count("{") != text.count("}"):
        return False

    known = {
        "daily", "weekly", "monthly", "yearly", "hourly", "size", "minsize", "maxsize",
        "rotate", "missingok", "nomissingok", "notifempty", "ifempty", "compress", "nocompress",
        "delaycompress", "nodelaycompress", "copytruncate", "nocopytruncate", "create", "nocreate",
        "olddir", "noolddir", "sharedscripts", "nosharedscripts", "dateext", "nodateext",
        "dateformat", "dateyesterday", "datehourago", "extension", "addextension", "start",
        "su", "mail", "nomail", "mailfirst", "maillast", "errors", "shred", "noshred",
        "shredcycles", "allowhardlink", "noallowhardlink", "prerotate", "postrotate",
        "firstaction", "lastaction", "endscript"
    }

    for match in re.finditer(r"([^{}]+)\{([^{}]*)\}", text, flags=re.S):
        header = match.group(1).strip().splitlines()[-1].strip()
        body = match.group(2)
        try:
            header_tokens = re.findall(r'"[^"]+"|\S+', header)
            paths = [token.strip('"') for token in header_tokens]
        except Exception:
            continue
        if TARGET_LOG not in paths or any(not p.startswith("/") for p in paths):
            continue

        daily = False
        in_script = False
        valid = True
        for line in body.splitlines():
            line = line.strip()
            if not line:
                continue
            word = line.split()[0]
            if in_script:
                if word == "endscript":
                    in_script = False
                continue
            if word not in known:
                valid = False
                break
            if word in {"prerotate", "postrotate", "firstaction", "lastaction"}:
                in_script = True
            if word == "daily" and len(line.split()) == 1:
                daily = True
        if not valid or in_script or not daily:
            continue

        logrotate = shutil.which("logrotate")
        if logrotate:
            checked = subprocess.run([logrotate, "-d", path], capture_output=True, text=True)
            if checked.returncode != 0:
                continue
        return True
    return False


def test_logrotate_config():
    """Verify a syntactically meaningful daily stanza for the target usage log."""
    found = any(has_valid_target_stanza(path) for path in candidate_logrotate_files())
    assert found, f"Could not find a valid logrotate stanza for {TARGET_LOG} specifying daily rotation."


def test_analyze_script_exists():
    """Verify that analyze.sh exists and is valid Bash syntax."""
    assert os.path.isfile(SCRIPT), f"Missing analyze script: {SCRIPT}"
    syntax = subprocess.run(["bash", "-n", SCRIPT], capture_output=True, text=True)
    assert syntax.returncode == 0, f"analyze.sh is not valid Bash: {syntax.stderr}"


def test_analyze_script_performs_regression():
    """Execute the submitted script against independently derived regression cases."""
    log_dir = os.path.dirname(TARGET_LOG)
    backup_dir = tempfile.mkdtemp(prefix="capacity-logs-")
    original_logs = glob.glob(TARGET_LOG + "*")
    pred_existed = os.path.isfile(PRED_FILE)
    pred_data = open(PRED_FILE, "rb").read() if pred_existed else None
    pred_stat = os.stat(PRED_FILE) if pred_existed else None

    for path in original_logs:
        shutil.move(path, os.path.join(backup_dir, os.path.basename(path)))

    datasets = []
    datasets.append([(x, 12.5 + 0.173 * x + 5.0 * math.sin(x * 0.37)) for x in range(1, 100)])
    datasets.append([(x, 145.0 - 0.61 * x + ((x % 11) - 5) * 1.7) for x in range(1, 100)])

    try:
        for rows in datasets:
            for path in glob.glob(TARGET_LOG + "*"):
                if os.path.isfile(path):
                    os.unlink(path)
            test_log = TARGET_LOG + ".1"
            with open(test_log, "w") as f:
                for x, cpu in rows:
                    f.write(f"{x} {cpu:.8f} {30.0 + (x % 7) / 10.0:.2f}\n")
            os.chmod(test_log, 0o644)

            expected = regression_prediction([(x, round(cpu, 8)) for x, cpu in rows])
            produced = run_analyzer()
            assert any((value - expected) ** 2 <= 1.0 for value in produced), (
                f"analyze.sh did not compute the timestamp-100 linear-regression prediction; "
                f"expected {expected:.6f}, got {produced}"
            )
    finally:
        for path in glob.glob(TARGET_LOG + "*"):
            if os.path.isfile(path):
                os.unlink(path)
        for name in os.listdir(backup_dir):
            shutil.move(os.path.join(backup_dir, name), os.path.join(log_dir, name))
        shutil.rmtree(backup_dir)

        if pred_existed:
            with open(PRED_FILE, "wb") as f:
                f.write(pred_data)
            os.chmod(PRED_FILE, pred_stat.st_mode & 0o7777)
            os.chown(PRED_FILE, pred_stat.st_uid, pred_stat.st_gid)
        elif os.path.exists(PRED_FILE):
            os.unlink(PRED_FILE)

    # Also execute the artifact on the real logs. Its result must agree with those logs.
    rows = []
    for path in glob.glob(TARGET_LOG + "*"):
        with open(path, "r") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 2:
                    try:
                        rows.append((float(parts[0]), float(parts[1])))
                    except ValueError:
                        pass
    assert len(rows) > 1
    expected = regression_prediction(rows)
    produced = run_analyzer()
    assert any((value - expected) ** 2 <= 1.0 for value in produced), (
        f"analyze.sh result on the real logs is incorrect; expected {expected:.6f}, got {produced}"
    )


def test_prediction_metric():
    """Verify the saved prediction using the original MSE threshold."""
    assert os.path.isfile(PRED_FILE), f"Missing prediction file: {PRED_FILE}"
    with open(PRED_FILE, "r") as f:
        pred_str = f.read().strip()
    try:
        pred = float(pred_str)
    except ValueError:
        pytest.fail(f"The file {PRED_FILE} does not contain a valid floating-point number. Found: '{pred_str}'")

    rows = []
    log_files = glob.glob(TARGET_LOG + "*")
    assert log_files, "No log files found for caching-service to calculate reference."
    for path in log_files:
        with open(path, "r") as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 2:
                    try:
                        rows.append((float(parts[0]), float(parts[1])))
                    except ValueError:
                        continue
    assert len(rows) > 1, "Not enough valid data points found in the logs to perform linear regression."
    ref = regression_prediction(rows)
    mse = (pred - ref) ** 2
    assert mse <= 1.0, f"Predicted value {pred} is too far from reference {ref:.2f}. MSE={mse:.4f} (Threshold <= 1.0)"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
