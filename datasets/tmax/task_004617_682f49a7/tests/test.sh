#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import multiprocessing
import os
import random
import secrets
import subprocess
import tempfile

import pytest


def test_audio_trigger():
    txt_path = "/home/user/audio_trigger.txt"
    assert os.path.isfile(txt_path), f"File {txt_path} is missing. You must transcribe the audio trigger."
    with open(txt_path, "r") as f:
        content = f.read().strip().lower()

    expected = "restart cluster maintenance override"
    assert content == expected, f"Incorrect audio transcription. Expected '{expected}', but got '{content}'."


def _parse_worker(processor_path, node, tree, queue):
    try:
        module_name = "submitted_processor_" + secrets.token_hex(8)
        spec = importlib.util.spec_from_file_location(module_name, processor_path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        result = module.parse_command_tree(node, tree)
        queue.put(("ok", result))
    except BaseException as exc:
        queue.put(("error", f"{type(exc).__name__}: {exc}"))


def _call_parse(processor_path, node, tree):
    ctx = multiprocessing.get_context("fork")
    queue = ctx.Queue()
    proc = ctx.Process(target=_parse_worker, args=(processor_path, node, tree, queue))
    proc.start()
    proc.join(3)
    if proc.is_alive():
        proc.terminate()
        proc.join()
        pytest.fail("parse_command_tree did not terminate")
    try:
        status, value = queue.get(timeout=1)
    except Exception:
        pytest.fail(f"parse_command_tree exited without returning a result (exit code {proc.exitcode})")
    assert status == "ok", f"parse_command_tree raised an exception: {value}"
    return value


def test_daemon_processor_fixed():
    processor_path = "/home/user/daemon/processor.py"
    assert os.path.isfile(processor_path), f"File {processor_path} is missing."

    result = subprocess.run(
        ["python3", processor_path, "--test"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    expected_output = '{"error": "circular reference detected"}'
    assert expected_output in result.stdout, (
        f"Processor did not return expected error JSON. "
        f"Expected to find '{expected_output}' in stdout. Output: {result.stdout}"
    )

    names = ["alias_" + secrets.token_hex(6) for _ in range(7)]
    acyclic = {
        names[0]: [names[1]],
        names[1]: [names[2]],
        names[2]: [names[3]],
        names[3]: [],
    }
    assert _call_parse(processor_path, names[0], acyclic) == names[1:4]

    cyclic = {
        names[0]: [names[1]],
        names[1]: [names[2]],
        names[2]: [names[3]],
        names[3]: [names[4]],
        names[4]: [names[1]],
    }
    assert _call_parse(processor_path, names[0], cyclic) == {
        "error": "circular reference detected"
    }

    self_cycle = {names[5]: [names[5]]}
    assert _call_parse(processor_path, names[5], self_cycle) == {
        "error": "circular reference detected"
    }


def _selected_filter():
    py_script = "/home/user/log_filter.py"
    sh_script = "/home/user/log_filter.sh"

    if os.path.isfile(py_script):
        script = py_script
        cmd_prefix = ["python3", py_script]
    elif os.path.isfile(sh_script):
        script = sh_script
        cmd_prefix = ["bash", sh_script]
    else:
        pytest.fail("Neither /home/user/log_filter.py nor /home/user/log_filter.sh found. You must create the log filter script.")

    assert os.access(script, os.X_OK), f"Log filter {script} must be executable."
    return cmd_prefix


def test_log_filter_adversarial():
    cmd_prefix = _selected_filter()
    evil_logs_dir = "/app/evil_logs/"
    clean_logs_dir = "/app/clean_logs/"

    assert os.path.isdir(evil_logs_dir), f"Evil logs directory missing at {evil_logs_dir}"
    assert os.path.isdir(clean_logs_dir), f"Clean logs directory missing at {clean_logs_dir}"

    evil_files = sorted([os.path.join(evil_logs_dir, f) for f in os.listdir(evil_logs_dir) if os.path.isfile(os.path.join(evil_logs_dir, f))])
    clean_files = sorted([os.path.join(clean_logs_dir, f) for f in os.listdir(clean_logs_dir) if os.path.isfile(os.path.join(clean_logs_dir, f))])

    assert len(evil_files) > 0, "No evil log files found to test."
    assert len(clean_files) > 0, "No clean log files found to test."

    evil_bypassed = []
    for f in evil_files:
        res = subprocess.run(cmd_prefix + [f], capture_output=True, timeout=5)
        if res.returncode != 1:
            evil_bypassed.append(os.path.basename(f))

    clean_modified = []
    for f in clean_files:
        res = subprocess.run(cmd_prefix + [f], capture_output=True, timeout=5)
        if res.returncode != 0:
            clean_modified.append(os.path.basename(f))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed (expected exit code 1): {', '.join(evil_bypassed[:5])}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (expected exit code 0): {', '.join(clean_modified[:5])}")

    if errors:
        pytest.fail(" | ".join(errors))


def _write_hidden_log(path, evil, rng):
    timestamp = rng.randint(1700000000, 1900000000)
    anomaly_at = rng.randint(15, 84)
    with open(path, "w") as f:
        for index in range(100):
            if evil and index == anomaly_at:
                timestamp -= rng.randint(7, 90)
                latency = rng.randint(501, 1400)
            else:
                timestamp += rng.randint(1, 5)
                latency = max(1, int(round(rng.normalvariate(15, 2))))
            f.write(f"{timestamp} INFO ping latency={latency}ms\n")


def test_log_filter_hidden_content_suite():
    cmd_prefix = _selected_filter()
    rng = random.SystemRandom()

    with tempfile.TemporaryDirectory(prefix="lf_" + secrets.token_hex(8) + "_") as hidden_dir:
        labels = [False] * 12 + [True] * 12
        rng.shuffle(labels)
        cases = []
        for evil in labels:
            path = os.path.join(hidden_dir, secrets.token_hex(16) + ".txt")
            _write_hidden_log(path, evil, rng)
            cases.append((path, 1 if evil else 0))

        rng.shuffle(cases)
        failures = []
        for path, expected_code in cases:
            result = subprocess.run(cmd_prefix + [path], capture_output=True, timeout=5)
            if result.returncode != expected_code:
                failures.append(
                    f"{os.path.basename(path)} returned {result.returncode}, expected {expected_code}"
                )
        assert not failures, "Hidden log classifications failed: " + "; ".join(failures[:5])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
