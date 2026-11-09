#!/bin/bash
set -u
mkdir -p /logs/verifier

# Reset all deployment inputs and outputs so only execution performed by this
# verifier can produce the observed result.
rm -rf /home/user/backups
rm -f /home/user/deploy.log /tmp/deploy_validation_trace.jsonl /tmp/deploy_run_status
mkdir -p /home/user/instances/inst{1,2,3,4,5}
for i in 1 2 3 4 5; do
    printf '%s\n' '{"version": "1.0", "theme": "blue"}' > "/home/user/instances/inst${i}/config.json"
done

# Install an instrumented implementation of the specified validator. It keeps
# the original validation behavior while recording independently observed
# configurations and validation timing.
cat << 'VALIDATE_EOF' > /home/user/validate.py
#!/usr/bin/env python3
import json
import os
import sys
import time

TRACE = "/tmp/deploy_validation_trace.jsonl"
INSTANCES = "/home/user/instances"

if len(sys.argv) != 2:
    sys.exit(1)

inst_dir = os.path.abspath(sys.argv[1])
inst = os.path.basename(inst_dir)
config_path = os.path.join(inst_dir, "config.json")

snapshots = {}
for name in ["inst1", "inst2", "inst3", "inst4", "inst5"]:
    path = os.path.join(INSTANCES, name, "config.json")
    try:
        with open(path, "r") as f:
            snapshots[name] = json.load(f)
    except Exception as exc:
        snapshots[name] = {"__error__": type(exc).__name__}

record = {
    "instance": inst,
    "time": time.monotonic(),
    "snapshots": snapshots,
}
with open(TRACE, "a") as f:
    f.write(json.dumps(record, sort_keys=True) + "\n")

try:
    with open(config_path, "r") as f:
        data = json.load(f)
except Exception:
    sys.exit(1)

# Preserve the environment's intentional failure condition.
if inst == "inst4" and data.get("version") == "2.0":
    sys.exit(1)
sys.exit(0)
VALIDATE_EOF
chmod 755 /home/user/validate.py

# Execute the submitted artifact. A nonzero application exit is tolerated for
# rollback handling, but a timeout is recorded and rejected by the tests.
if timeout 15s python3 /home/user/deploy.py; then
    run_rc=0
else
    run_rc=$?
fi
printf '%s\n' "$run_rc" > /tmp/deploy_run_status

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pytest

OLD = {"version": "1.0", "theme": "blue"}
NEW = {"version": "2.0", "theme": "green"}


def read_json(path):
    with open(path, "r") as f:
        return json.load(f)


def read_log():
    with open('/home/user/deploy.log', 'r') as f:
        return [line.strip() for line in f if line.strip()]


def read_trace():
    path = '/tmp/deploy_validation_trace.jsonl'
    assert os.path.isfile(path), "The deployment never invoked the validator."
    with open(path, 'r') as f:
        return [json.loads(line) for line in f if line.strip()]


def test_deploy_script_exists():
    assert os.path.isfile('/home/user/deploy.py'), "The deployment script /home/user/deploy.py does not exist."


def test_deploy_was_executed_without_timeout():
    with open('/tmp/deploy_run_status', 'r') as f:
        rc = int(f.read().strip())
    assert rc != 124, "The deployment script did not exit before the timeout."


def test_deploy_log_content():
    log_path = '/home/user/deploy.log'
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."
    lines = read_log()

    # Preserve the original log assertions.
    assert "INFO: Backup inst1" in lines, "Missing backup log for inst1."
    assert "INFO: Update inst1" in lines, "Missing update log for inst1."
    assert "INFO: Backup inst2" in lines, "Missing backup log for inst2."
    assert "INFO: Update inst2" in lines, "Missing update log for inst2."
    assert "INFO: Validate inst1 - SUCCESS" in lines, "Missing successful validation log for inst1."
    assert "INFO: Validate inst2 - SUCCESS" in lines, "Missing successful validation log for inst2."
    assert "INFO: Backup inst3" in lines, "Missing backup log for inst3."
    assert "INFO: Update inst3" in lines, "Missing update log for inst3."
    assert "INFO: Backup inst4" in lines, "Missing backup log for inst4."
    assert "INFO: Update inst4" in lines, "Missing update log for inst4."
    assert "ERROR: Validate inst4 - FAILED" in lines, "Missing failed validation log for inst4."

    try:
        idx_rb4 = lines.index("INFO: Rollback inst4")
        idx_rb3 = lines.index("INFO: Rollback inst3")
        idx_rb2 = lines.index("INFO: Rollback inst2")
        idx_rb1 = lines.index("INFO: Rollback inst1")
        idx_complete = lines.index("CRITICAL: Rollback complete")
        assert idx_rb4 < idx_rb3 < idx_rb2 < idx_rb1 < idx_complete, \
            "Rollback logs are not in the exact reverse order of updates."
    except ValueError as e:
        pytest.fail(f"Missing rollback log entries or not in expected format: {e}")

    assert "INFO: Validate inst3 - SUCCESS" in lines, "Missing successful validation log for inst3."
    assert "SUCCESS: Deployment complete" not in lines, "A failed deployment was logged as successful."
    assert lines.index("ERROR: Validate inst4 - FAILED") < idx_rb4


def test_validator_observed_staged_updates_and_wait():
    trace = read_trace()
    assert [entry["instance"] for entry in trace] == ["inst1", "inst2", "inst3", "inst4"], \
        "Instances were not validated in the required batches before aborting."

    # During batch 1 validation, both members must already be updated while
    # later instances remain untouched.
    for entry in trace[:2]:
        snap = entry["snapshots"]
        assert snap["inst1"] == NEW
        assert snap["inst2"] == NEW
        assert snap["inst3"] == OLD
        assert snap["inst4"] == OLD
        assert snap["inst5"] == OLD

    # During batch 2 validation, the first four instances must be updated and
    # inst5 must still be untouched.
    for entry in trace[2:]:
        snap = entry["snapshots"]
        for name in ["inst1", "inst2", "inst3", "inst4"]:
            assert snap[name] == NEW
        assert snap["inst5"] == OLD

    # There must be an actual one-second inter-batch pause, allowing a small
    # scheduling tolerance.
    assert trace[2]["time"] - trace[1]["time"] >= 0.85, \
        "The deployment did not wait one second between batches."


def test_configs_restored():
    expected_config = {"version": "1.0", "theme": "blue"}
    for i in range(1, 6):
        config_path = f"/home/user/instances/inst{i}/config.json"
        assert os.path.isfile(config_path), f"Config file {config_path} does not exist."
        try:
            data = read_json(config_path)
        except json.JSONDecodeError:
            pytest.fail(f"Config file {config_path} is not valid JSON.")
        assert data == expected_config, f"Config file {config_path} was not restored to the initial state."


def test_backups_created():
    for i in range(1, 5):
        backup_path = f"/home/user/backups/inst{i}_config.json.bak"
        assert os.path.isfile(backup_path), f"Backup file {backup_path} should exist."
        assert read_json(backup_path) == OLD, f"Backup for inst{i} does not contain the original configuration."

    backup_path_5 = "/home/user/backups/inst5_config.json.bak"
    assert not os.path.exists(backup_path_5), \
        f"Backup file {backup_path_5} should not exist since inst5 was never reached."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
