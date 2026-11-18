#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import subprocess
import tempfile
import uuid

import pytest

VENDOR_DIR = "/app/vendor/async-log-parser-0.2.1"
CLASSIFIER_PATH = "/home/user/classifier.py"
_installed = False


def ensure_editable_install():
    global _installed
    if _installed:
        return
    assert os.path.isdir(VENDOR_DIR), f"Vendored package missing at {VENDOR_DIR}"
    result = subprocess.run(
        ["python3", "-m", "pip", "install", "-e", "."],
        cwd=VENDOR_DIR,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        "Vendored package cannot be installed with pip install -e .:\n"
        f"{result.stdout}\n{result.stderr}"
    )
    _installed = True


def run_classifier(input_dir, output_path):
    result = subprocess.run(
        ["python3", CLASSIFIER_PATH, input_dir, output_path],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Classifier failed for {input_dir}:\n{result.stdout}\n{result.stderr}"
    )
    assert os.path.isfile(output_path), "Classifier did not produce output JSON."
    with open(output_path, "r") as f:
        result_json = json.load(f)
    assert isinstance(result_json, dict), "Classifier output must be a JSON object."
    return result_json


def expected_label(lines):
    cancel_re = re.compile(r"\[CANCEL\]\s+Task\s+(\S+)\s+interrupted")
    cleanup_re = re.compile(r"\[CLEANUP\]\s+Task\s+(\S+)\s+resources released")
    later_cleanups = set()
    never_subsequently_cleaned = set()
    for line in reversed(lines):
        cleanup = cleanup_re.search(line)
        if cleanup:
            later_cleanups.add(cleanup.group(1))
        cancel = cancel_re.search(line)
        if cancel and cancel.group(1) not in later_cleanups:
            never_subsequently_cleaned.add(cancel.group(1))
    return "evil" if len(never_subsequently_cleaned) >= 5 else "clean"


def event(kind, task_id):
    if kind == "cancel":
        message = f"[CANCEL] Task {task_id} interrupted"
    elif kind == "cleanup":
        message = f"[CLEANUP] Task {task_id} resources released"
    else:
        message = f"[START] Task {task_id} started"
    return f"10:00:{random.randrange(60):02d} - {message}"


def test_classifier_accuracy():
    ensure_editable_install()
    assert os.path.isfile(CLASSIFIER_PATH), f"Classifier script not found at {CLASSIFIER_PATH}"

    clean_dir = "/home/user/corpora/clean"
    evil_dir = "/home/user/corpora/evil"

    with tempfile.TemporaryDirectory() as tmpdir:
        clean_out = os.path.join(tmpdir, "clean_out.json")
        evil_out = os.path.join(tmpdir, "evil_out.json")

        clean_results = run_classifier(clean_dir, clean_out)
        evil_results = run_classifier(evil_dir, evil_out)

    clean_files = [f for f in os.listdir(clean_dir) if f.endswith('.log')]
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith('.log')]

    clean_modified = []
    for cf in clean_files:
        if clean_results.get(cf) != "clean":
            clean_modified.append(cf)

    evil_bypassed = []
    for ef in evil_files:
        if evil_results.get(ef) != "evil":
            evil_bypassed.append(ef)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")

    assert not errors, " | ".join(errors)


def test_classifier_on_mixed_hidden_logs():
    ensure_editable_install()
    assert os.path.isfile(CLASSIFIER_PATH), f"Classifier script not found at {CLASSIFIER_PATH}"

    base = random.randrange(10000, 90000)
    ids = [str(base + i) for i in range(80)]
    cases = []

    # At least five cancellations, but all have subsequent cleanup: clean.
    lines = ["malformed line with no separator"]
    for task_id in ids[0:7]:
        lines.append(event("cancel", task_id))
    for task_id in ids[0:7]:
        lines.append(event("cleanup", task_id))
    cases.append(lines)

    # Four never-cleaned cancellations are below the threshold: clean.
    lines = [event("cancel", task_id) for task_id in ids[10:14]]
    lines += [event("start", ids[14]), "another malformed line"]
    cases.append(lines)

    # Exactly five never-cleaned cancellations: evil.
    lines = [event("cancel", task_id) for task_id in ids[20:25]]
    cases.append(lines)

    # Cleanup before cancellation does not count as subsequent cleanup: evil.
    lines = [event("cleanup", task_id) for task_id in ids[30:35]]
    lines += [event("cancel", task_id) for task_id in ids[30:35]]
    cases.append(lines)

    # Some cancellations are cleaned later, leaving only four unmatched: clean.
    lines = [event("cancel", task_id) for task_id in ids[40:47]]
    lines += [event("cleanup", task_id) for task_id in ids[40:43]]
    cases.append(lines)

    # Mixed paired and unpaired tasks, with six unmatched: evil.
    lines = []
    for task_id in ids[50:58]:
        lines.append(event("cancel", task_id))
    lines += [event("cleanup", ids[50]), event("cleanup", ids[51])]
    lines += ["", "not a standard log record"]
    cases.append(lines)

    random.shuffle(cases)

    with tempfile.TemporaryDirectory(prefix="mixed-corpus-") as input_dir, \
         tempfile.TemporaryDirectory() as output_dir:
        expected = {}
        for lines in cases:
            filename = f"{uuid.uuid4().hex}.log"
            with open(os.path.join(input_dir, filename), "w") as f:
                f.write("\n".join(lines) + "\n")
            expected[filename] = expected_label(lines)

        with open(os.path.join(input_dir, f"{uuid.uuid4().hex}.txt"), "w") as f:
            f.write("This non-log file must be ignored.\n")

        output_path = os.path.join(output_dir, "results.json")
        actual = run_classifier(input_dir, output_path)

    assert set(actual) == set(expected), (
        f"Output keys must exactly match the .log files. Expected {sorted(expected)}, "
        f"got {sorted(actual)}"
    )
    assert actual == expected, f"Incorrect hidden classifications: expected {expected}, got {actual}"
    assert "clean" in expected.values() and "evil" in expected.values()


def test_package_fixed():
    ensure_editable_install()
    # Verify the package can be imported and doesn't crash on empty/malformed lines.
    test_script = r'''
import os
import sys
try:
    import async_log_parser
    from async_log_parser import parse_file
except ImportError as e:
    print(f"ImportError: {e}")
    sys.exit(1)

vendor = os.path.realpath("/app/vendor/async-log-parser-0.2.1")
module_path = os.path.realpath(async_log_parser.__file__)
if os.path.commonpath([vendor, module_path]) != vendor:
    print(f"Imported package is not the editable vendored package: {module_path}")
    sys.exit(4)

with open('dummy.log', 'w') as f:
    f.write('malformed line without separator\n')
    f.write('10:00:00 - [START] Task 1\n')

try:
    events = parse_file('dummy.log')
    if len(events) != 2:
        sys.exit(2)
    if events[0].get('raw') != 'malformed line without separator':
        sys.exit(5)
    if events[0].get('timestamp') != '' or events[0].get('message') != 'malformed line without separator':
        sys.exit(6)
    if events[1].get('timestamp') != '10:00:00' or events[1].get('message') != '[START] Task 1':
        sys.exit(7)
except Exception as e:
    print(f"Crash: {e}")
    sys.exit(3)
'''
    with tempfile.TemporaryDirectory() as tmpdir:
        script_path = os.path.join(tmpdir, "test_pkg.py")
        with open(script_path, "w") as f:
            f.write(test_script)

        res = subprocess.run(["python3", script_path], cwd=tmpdir, capture_output=True, text=True)
        assert res.returncode == 0, f"Vendored package is still broken or not installed properly:\n{res.stdout}\n{res.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
