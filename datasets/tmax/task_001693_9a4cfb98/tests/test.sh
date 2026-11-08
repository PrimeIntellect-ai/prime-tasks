#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import shutil
import stat
import subprocess
import tempfile
import uuid

import pytest

VALIDATE_SCRIPT = "/home/user/validate_payload"
SUPERVISOR_SCRIPT = "/home/user/supervisor.sh"
PARSER = "/app/sensor_parser"
CLEAN_CORPUS_DIR = "/app/corpus/clean"
EVIL_CORPUS_DIR = "/app/corpus/evil"
SPOOL_INCOMING = "/home/user/spool/incoming"
SPOOL_PROCESSED = "/home/user/spool/processed"
SPOOL_QUARANTINE = "/home/user/spool/quarantine"


def run_validator(path):
    return subprocess.run(
        [VALIDATE_SCRIPT, path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )


def test_validate_payload_exists_and_executable():
    assert os.path.exists(VALIDATE_SCRIPT), f"{VALIDATE_SCRIPT} does not exist."
    assert os.path.isfile(VALIDATE_SCRIPT), f"{VALIDATE_SCRIPT} is not a file."
    assert os.access(VALIDATE_SCRIPT, os.X_OK), f"{VALIDATE_SCRIPT} is not executable."


def test_supervisor_script_exists_and_executable():
    assert os.path.exists(SUPERVISOR_SCRIPT), f"{SUPERVISOR_SCRIPT} does not exist."
    assert os.path.isfile(SUPERVISOR_SCRIPT), f"{SUPERVISOR_SCRIPT} is not a file."
    assert os.access(SUPERVISOR_SCRIPT, os.X_OK), f"{SUPERVISOR_SCRIPT} is not executable."


def test_spool_directories_and_permissions():
    for d in [SPOOL_INCOMING, SPOOL_PROCESSED, SPOOL_QUARANTINE]:
        assert os.path.exists(d), f"Directory {d} does not exist."
        assert os.path.isdir(d), f"{d} is not a directory."

    incoming_stat = os.stat(SPOOL_INCOMING)
    perms = stat.S_IMODE(incoming_stat.st_mode)
    assert perms == 0o733, f"Permissions of {SPOOL_INCOMING} are {oct(perms)}, expected 0o733."


def test_adversarial_corpus_clean():
    clean_files = [os.path.join(CLEAN_CORPUS_DIR, f) for f in os.listdir(CLEAN_CORPUS_DIR) if os.path.isfile(os.path.join(CLEAN_CORPUS_DIR, f))]
    assert clean_files, f"No files found in clean corpus {CLEAN_CORPUS_DIR}"

    failed_files = []
    for f in clean_files:
        result = run_validator(f)
        if result.returncode != 0:
            failed_files.append(os.path.basename(f))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files rejected (should be accepted). Offending files: {', '.join(failed_files)}")


def test_adversarial_corpus_evil():
    evil_files = [os.path.join(EVIL_CORPUS_DIR, f) for f in os.listdir(EVIL_CORPUS_DIR) if os.path.isfile(os.path.join(EVIL_CORPUS_DIR, f))]
    assert evil_files, f"No files found in evil corpus {EVIL_CORPUS_DIR}"

    failed_files = []
    for f in evil_files:
        result = run_validator(f)
        if result.returncode == 0:
            failed_files.append(os.path.basename(f))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed (should be rejected). Offending files: {', '.join(failed_files)}")


def test_validator_on_generated_structural_cases():
    # These randomized fixtures prevent recognition of the shipped paths, names,
    # or exact corpus contents. Expected results are derived from the format.
    with tempfile.TemporaryDirectory(prefix="payload-check-") as td:
        cases = []

        def add_case(declared, payload, expected_valid, magic=b"SENS", header=True):
            name = uuid.uuid4().hex + ".telemetry"
            path = os.path.join(td, name)
            if header:
                data = magic + declared.to_bytes(2, "big") + payload
            else:
                data = payload
            with open(path, "wb") as f:
                f.write(data)
            cases.append((path, expected_valid))

        # Safe parser inputs: empty, exact-sized, and payloads with trailing data.
        add_case(0, b"", True)
        for declared in (1, 7, 31, 257, 4096):
            extra = int.from_bytes(os.urandom(1), "big") % 9
            add_case(declared, os.urandom(declared + extra), True)

        # Crash-inducing inputs where the declared length exceeds available data.
        for declared, actual in ((1, 0), (8, 7), (128, 3), (4097, 4096), (65535, 37)):
            add_case(declared, os.urandom(actual), False)

        # Other malformed structures must also be rejected.
        add_case(4, b"ABCD", False, magic=b"NOPE")
        add_case(0, b"", False, header=False)
        add_case(0, b"SENS\x00", False, header=False)

        for path, expected_valid in cases:
            result = run_validator(path)
            assert (result.returncode == 0) == expected_valid, (
                f"validator returned {result.returncode} for generated case "
                f"{os.path.basename(path)}; expected valid={expected_valid}"
            )


def _clear_directory(path):
    for name in os.listdir(path):
        target = os.path.join(path, name)
        if os.path.isdir(target) and not os.path.islink(target):
            shutil.rmtree(target)
        else:
            os.unlink(target)


def test_supervisor_processes_quarantines_invokes_and_deletes():
    for directory in (SPOOL_INCOMING, SPOOL_PROCESSED, SPOOL_QUARANTINE):
        _clear_directory(directory)

    nonce = uuid.uuid4().hex
    valid_marker = ("VALID-" + nonce).encode()
    invalid_marker = ("INVALID-" + nonce).encode()
    parser_output = ("parser-invoked-" + nonce + "\n").encode()
    validator_log = os.path.join("/tmp", "validator-log-" + nonce)
    parser_log = os.path.join("/tmp", "parser-log-" + nonce)

    names_and_data = {
        "valid one " + nonce + ".bin": valid_marker + b"-A",
        "valid-two-" + nonce + ".bin": valid_marker + b"-B",
        "evil one " + nonce + ".bin": invalid_marker + b"-A",
        "evil-two-" + nonce + ".bin": invalid_marker + b"-B",
    }
    valid_names = {name for name, data in names_and_data.items() if data.startswith(valid_marker)}
    invalid_names = set(names_and_data) - valid_names

    for name, data in names_and_data.items():
        with open(os.path.join(SPOOL_INCOMING, name), "wb") as f:
            f.write(data)

    validator_backup = VALIDATE_SCRIPT + ".verifier-backup-" + nonce
    parser_backup = PARSER + ".verifier-backup-" + nonce
    os.replace(VALIDATE_SCRIPT, validator_backup)
    os.replace(PARSER, parser_backup)

    validator_wrapper = f'''#!/usr/bin/env python3
import os, sys
with open({validator_log!r}, "a", encoding="utf-8") as log:
    log.write(os.path.basename(sys.argv[1]) + "\\n")
with open(sys.argv[1], "rb") as payload:
    data = payload.read()
sys.exit(0 if data.startswith({valid_marker!r}) else 1)
'''
    parser_wrapper = f'''#!/usr/bin/env python3
import os, sys
with open({parser_log!r}, "a", encoding="utf-8") as log:
    log.write(os.path.basename(sys.argv[1]) + "\\n")
sys.stdout.buffer.write({parser_output!r})
'''

    try:
        with open(VALIDATE_SCRIPT, "w", encoding="utf-8") as f:
            f.write(validator_wrapper)
        os.chmod(VALIDATE_SCRIPT, 0o755)
        with open(PARSER, "w", encoding="utf-8") as f:
            f.write(parser_wrapper)
        os.chmod(PARSER, 0o755)

        result = subprocess.run(
            [SUPERVISOR_SCRIPT],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"supervisor exited {result.returncode}; stderr={result.stderr.decode(errors='replace')}"
        )

        assert os.path.exists(validator_log), "supervisor never invoked /home/user/validate_payload"
        with open(validator_log, encoding="utf-8") as f:
            validated = [line.rstrip("\n") for line in f]
        counts = collections.Counter(validated)
        for name in names_and_data:
            assert counts[name] >= 1, f"supervisor did not validate incoming file {name!r}"

        assert os.path.exists(parser_log), "supervisor never invoked /app/sensor_parser"
        with open(parser_log, encoding="utf-8") as f:
            parsed = [line.rstrip("\n") for line in f]
        assert set(parsed) == valid_names, (
            f"parser invocations were {parsed!r}; expected only valid files {sorted(valid_names)!r}"
        )

        for name in valid_names:
            processed = os.path.join(SPOOL_PROCESSED, name)
            assert os.path.isfile(processed), f"valid file {name!r} was not processed"
            with open(processed, "rb") as f:
                assert f.read() == parser_output, "parser stdout was not saved as required"
            assert not os.path.exists(os.path.join(SPOOL_QUARANTINE, name))

        for name in invalid_names:
            quarantined = os.path.join(SPOOL_QUARANTINE, name)
            assert os.path.isfile(quarantined), f"invalid file {name!r} was not quarantined"
            with open(quarantined, "rb") as f:
                assert f.read() == names_and_data[name], "quarantined payload was altered"
            assert not os.path.exists(os.path.join(SPOOL_PROCESSED, name))

        assert os.listdir(SPOOL_INCOMING) == [], "supervisor did not remove/move all incoming files"
    finally:
        if os.path.lexists(VALIDATE_SCRIPT):
            os.unlink(VALIDATE_SCRIPT)
        if os.path.lexists(PARSER):
            os.unlink(PARSER)
        os.replace(validator_backup, VALIDATE_SCRIPT)
        os.replace(parser_backup, PARSER)
        for log in (validator_log, parser_log):
            if os.path.exists(log):
                os.unlink(log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
