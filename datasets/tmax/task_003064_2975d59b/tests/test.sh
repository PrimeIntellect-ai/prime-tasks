#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import subprocess
import pytest

DETECTOR_SCRIPT = "/home/user/detector.py"
EVIL_CORPUS_DIR = "/opt/verifier/corpus/evil"
CLEAN_CORPUS_DIR = "/opt/verifier/corpus/clean"


def run_detector(input_dir, output_log):
    assert os.path.exists(DETECTOR_SCRIPT), f"Detector script not found at {DETECTOR_SCRIPT}"
    assert os.path.isfile(DETECTOR_SCRIPT), f"Detector path is not a regular file: {DETECTOR_SCRIPT}"
    result = subprocess.run(
        ["python3", DETECTOR_SCRIPT, input_dir, output_log],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"Detector script failed with return code {result.returncode}.\nStderr: {result.stderr}"


def read_flagged(output_log):
    with open(output_log, "r") as f:
        return set(line.strip() for line in f if line.strip())


def test_detector_evil_corpus(tmp_path):
    output_log = str(tmp_path / "evil_out.txt")
    run_detector(EVIL_CORPUS_DIR, output_log)

    assert os.path.exists(output_log), f"Output log not created: {output_log}"

    with open(output_log, "r") as f:
        flagged_files = set(line.strip() for line in f if line.strip())

    expected_evil_files = set(os.listdir(EVIL_CORPUS_DIR))

    missed_evil = expected_evil_files - flagged_files
    extra_evil = flagged_files - expected_evil_files

    error_msg = ""
    if missed_evil:
        error_msg += f"{len(missed_evil)} of {len(expected_evil_files)} evil bypassed (not flagged). Missing: {', '.join(sorted(missed_evil))}\n"
    if extra_evil:
        error_msg += f"Flagged non-existent files in evil corpus: {', '.join(sorted(extra_evil))}\n"

    assert not missed_evil and not extra_evil, error_msg


def test_detector_clean_corpus(tmp_path):
    output_log = str(tmp_path / "clean_out.txt")
    run_detector(CLEAN_CORPUS_DIR, output_log)

    if not os.path.exists(output_log):
        flagged_files = set()
    else:
        with open(output_log, "r") as f:
            flagged_files = set(line.strip() for line in f if line.strip())

    expected_clean_files = set(os.listdir(CLEAN_CORPUS_DIR))

    falsely_flagged = flagged_files.intersection(expected_clean_files)
    extra_flagged = flagged_files - expected_clean_files

    error_msg = ""
    if falsely_flagged:
        error_msg += f"{len(falsely_flagged)} of {len(expected_clean_files)} clean modified (falsely flagged). Offending: {', '.join(sorted(falsely_flagged))}\n"
    if extra_flagged:
        error_msg += f"Flagged non-existent files in clean corpus: {', '.join(sorted(extra_flagged))}\n"

    assert not falsely_flagged and not extra_flagged, error_msg


def test_detector_novel_mixed_corpus(tmp_path):
    token = secrets.token_hex(8)
    user = "acct_" + secrets.token_hex(5)
    password = "pw_" + secrets.token_hex(7)
    batch = tmp_path / ("batch_" + secrets.token_hex(6))
    batch.mkdir()

    vulnerable = f"/usr/local/bin/check_user --auth-method legacy -U '{user}' -P '{password}'"
    injected_user = f"/usr/local/bin/check_user --auth-method legacy -U '{user}'; /usr/bin/id; echo '' -P '{password}'"
    injected_password = f"/usr/local/bin/check_user --auth-method legacy -U '{user}' -P '{password}'; /bin/cat /etc/shadow; echo ''"

    cases = [
        (True, ["/bin/sh", "-c", vulnerable]),
        (True, ["/bin/sh", "-c", injected_user]),
        (True, ["/bin/sh", "-c", injected_password]),
        (True, ["/bin/sh", "-c", f"/usr/local/bin/check_user --auth-method legacy -U 'root' -P '{token}'"]),
        (False, ["/bin/bash", "-c", "echo hello " + token]),
        (False, ["/bin/sh", "-c", f"/usr/local/bin/check_user --auth-method new -U '{user}' -P '{password}'"]),
        (False, ["/usr/local/bin/check_user", "--auth-method", "legacy", "-U", user, "-P", password]),
        (False, ["/bin/sh", "-c", f"/usr/local/bin/check_user --auth-method legacy -U '{user}'"]),
        (False, ["/bin/sh", "-c", f"/usr/local/bin/check_user --auth-method legacy -P '{password}' -U '{user}'"]),
        (False, ["/bin/sh", "-c", f"printf %s {json.dumps(vulnerable)}"]),
        (False, ["/bin/sh", "-c", f"/usr/local/bin/check_user_backup --auth-method legacy -U '{user}' -P '{password}'"]),
    ]
    random.SystemRandom().shuffle(cases)

    expected = set()
    all_names = set()
    for is_malicious, event in cases:
        name = secrets.token_hex(10) + ".json"
        all_names.add(name)
        if is_malicious:
            expected.add(name)
        with open(batch / name, "w") as f:
            json.dump(event, f)

    output_log = str(tmp_path / ("results_" + secrets.token_hex(5) + ".txt"))
    run_detector(str(batch), output_log)
    assert os.path.exists(output_log), f"Output log not created: {output_log}"

    flagged = read_flagged(output_log)
    assert flagged <= all_names, f"Flagged non-existent files: {sorted(flagged - all_names)}"
    assert flagged == expected, (
        f"Novel mixed corpus classified incorrectly. "
        f"Missing: {sorted(expected - flagged)}; false positives: {sorted(flagged - expected)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
