#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import collections
import csv
import glob
import os
import random
import secrets
import shlex
import shutil
import subprocess
import tempfile
from datetime import datetime, timedelta

import pytest

SCRIPT_PATH = "/home/user/classifier.sh"
CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"
CHECKER_PATH = "/app/config_checker"


@pytest.fixture(scope="session", autouse=True)
def instrument_config_checker():
    state_dir = tempfile.mkdtemp(prefix="verifier_checker_")
    real_checker = os.path.join(state_dir, "config_checker.real")
    calls_dir = os.path.join(state_dir, "calls")
    marker = os.path.join(state_dir, "record_calls")
    os.mkdir(calls_dir)
    shutil.copy2(CHECKER_PATH, real_checker)

    wrapper = f"""#!/bin/bash
if [ -f {shlex.quote(marker)} ]; then
    call_file=$(mktemp {shlex.quote(calls_dir)}/call.XXXXXX) || exit 125
    cat > \"$call_file\"
    {shlex.quote(real_checker)} < \"$call_file\"
    exit $?
else
    exec {shlex.quote(real_checker)}
fi
"""
    with open(CHECKER_PATH, "w") as f:
        f.write(wrapper)
    os.chmod(CHECKER_PATH, 0o755)

    yield {
        "real_checker": real_checker,
        "calls_dir": calls_dir,
        "marker": marker,
    }

    shutil.copy2(real_checker, CHECKER_PATH)
    os.chmod(CHECKER_PATH, 0o755)
    shutil.rmtree(state_dir, ignore_errors=True)


def test_classifier_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable."


def test_clean_corpus():
    clean_files = sorted(glob.glob(os.path.join(CLEAN_DIR, "*")))
    assert len(clean_files) > 0, f"No files found in {CLEAN_DIR}"

    failed_files = []
    for fpath in clean_files:
        res = subprocess.run([SCRIPT_PATH, fpath], capture_output=True)
        if res.returncode != 0:
            failed_files.append(os.path.basename(fpath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean files modified/rejected (should be accepted with exit code 0). "
                    f"Offending files: {', '.join(failed_files)}")


def test_evil_corpus():
    evil_files = sorted(glob.glob(os.path.join(EVIL_DIR, "*")))
    assert len(evil_files) > 0, f"No files found in {EVIL_DIR}"

    failed_files = []
    for fpath in evil_files:
        res = subprocess.run([SCRIPT_PATH, fpath], capture_output=True)
        if res.returncode == 0:
            failed_files.append(os.path.basename(fpath))

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil files bypassed (should be rejected with exit code 1). "
                    f"Offending files: {', '.join(failed_files)}")


def encode_payload(text, encoding):
    if encoding == "plain_utf8":
        return text
    raw = text.encode("utf-8" if encoding == "base64_utf8" else "utf-16le")
    return base64.b64encode(raw).decode("ascii")


def decode_payload(encoding, payload):
    if encoding == "plain_utf8":
        return payload.encode("utf-8")
    raw = base64.b64decode(payload, validate=True)
    if encoding == "base64_utf8":
        return raw.decode("utf-8").encode("utf-8")
    if encoding == "base64_utf16le":
        return raw.decode("utf-16le").encode("utf-8")
    raise AssertionError(f"Unexpected encoding: {encoding}")


def oracle_result(rows, real_checker):
    counts = collections.Counter()
    checker_failed = False
    decoded = []
    for timestamp, device, encoding, payload in rows:
        hour = datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%SZ").strftime("%Y-%m-%dT%H")
        counts[(device, hour)] += 1
        data = decode_payload(encoding, payload)
        decoded.append(data)
        result = subprocess.run([real_checker], input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode != 0:
            checker_failed = True
    flooded = any(value > 50 for value in counts.values())
    return (1 if checker_failed or flooded else 0), decoded


def make_row(moment, device, encoding, text):
    return (
        moment.strftime("%Y-%m-%dT%H:%M:%SZ"),
        device,
        encoding,
        encode_payload(text, encoding),
    )


def test_generated_semantic_cases(tmp_path, instrument_config_checker):
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    token = secrets.token_hex(8)
    encodings = ["plain_utf8", "base64_utf8", "base64_utf16le"]
    base = datetime(2024 + rng.randrange(0, 2), rng.randrange(1, 13), rng.randrange(1, 20), rng.randrange(1, 20), 0, 0)

    def benign(i):
        return f"setting_{token}_{i}=value_{rng.randrange(100000, 999999)}"

    cases = []

    mixed = [
        make_row(base + timedelta(minutes=2 * i), f"NODE-{i % 4}-{token[:4]}", encodings[i % 3], benign(i))
        for i in range(18)
    ]
    cases.append((mixed, True))

    boundary = [
        make_row(base + timedelta(seconds=60 * i), f"BOUNDARY-{token}", encodings[i % 3], benign(100 + i))
        for i in range(50)
    ]
    cases.append((boundary, True))

    split_hours = []
    for i in range(30):
        split_hours.append(make_row(base + timedelta(minutes=i), f"SPLIT-{token}", encodings[i % 3], benign(200 + i)))
    for i in range(30):
        split_hours.append(make_row(base + timedelta(hours=1, minutes=i), f"SPLIT-{token}", encodings[(i + 1) % 3], benign(300 + i)))
    cases.append((split_hours, True))

    two_devices = []
    for i in range(50):
        moment = base + timedelta(seconds=i)
        two_devices.append(make_row(moment, f"PAIR-A-{token}", encodings[i % 3], benign(400 + i)))
        two_devices.append(make_row(moment, f"PAIR-B-{token}", encodings[(i + 1) % 3], benign(500 + i)))
    rng.shuffle(two_devices)
    cases.append((two_devices, True))

    triggers = [
        f"download_wget_{token}",
        f"remove_{token};now",
        f"run_eval({token})",
        f"substitute_$()_{token}",
    ]
    for case_number, trigger in enumerate(triggers):
        rows = [
            make_row(base + timedelta(minutes=2 * i), f"CONTENT-{case_number}-{token}", encodings[i % 3], benign(700 + case_number * 20 + i))
            for i in range(17)
        ]
        rows.append(make_row(base + timedelta(minutes=40), f"CONTENT-{case_number}-{token}", encodings[case_number % 3], trigger))
        cases.append((rows, True))

    flood = [
        make_row(base + timedelta(seconds=i), f"FLOOD-{token}", encodings[i % 3], benign(900 + i))
        for i in range(51)
    ]
    cases.append((flood, False))

    expected_classes = []
    for index, (rows, require_all_checked) in enumerate(cases):
        expected, decoded = oracle_result(rows, instrument_config_checker["real_checker"])
        expected_classes.append(expected)
        path = tmp_path / f"sample_{secrets.token_hex(10)}_{index}.csv"
        with path.open("w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerows(rows)

        for old_call in glob.glob(os.path.join(instrument_config_checker["calls_dir"], "call.*")):
            os.unlink(old_call)
        with open(instrument_config_checker["marker"], "w"):
            pass
        try:
            result = subprocess.run([SCRIPT_PATH, str(path)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
        finally:
            os.unlink(instrument_config_checker["marker"])

        assert result.returncode == expected, (
            f"Generated case {index} expected exit code {expected}, got {result.returncode}. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )

        if require_all_checked:
            observed = collections.Counter()
            for call_path in glob.glob(os.path.join(instrument_config_checker["calls_dir"], "call.*")):
                with open(call_path, "rb") as f:
                    observed[f.read()] += 1
            missing = collections.Counter(decoded) - observed
            assert not missing, (
                f"Generated case {index} did not pass every decoded payload to /app/config_checker; "
                f"missing {sum(missing.values())} checker invocation(s)."
            )

    assert 0 in expected_classes and 1 in expected_classes
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
