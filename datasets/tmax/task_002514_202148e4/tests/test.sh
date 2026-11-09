#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import shlex
import stat
import string
import subprocess
import tempfile
import time
import uuid

import pytest

FILTER = "/home/user/filter_and_fill.sh"
BATCH = "/home/user/batch_process.sh"


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=20, **kwargs)


def gap_fill(lines):
    output = []
    prev_ts = None
    prev_sensor = None
    prev_reading = None

    for line in lines:
        line = line.strip()
        if not line:
            continue

        parts = line.split(',')
        if len(parts) != 3 or parts[0] == "timestamp_sec":
            output.append(line)
            continue

        try:
            ts = int(parts[0])
        except ValueError:
            output.append(line)
            continue

        sensor = parts[1]
        reading = parts[2]
        if prev_ts is not None and ts > prev_ts + 1:
            for fill_ts in range(prev_ts + 1, ts):
                output.append(f"{fill_ts},{prev_sensor},{prev_reading}")

        output.append(line)
        prev_ts = ts
        prev_sensor = sensor
        prev_reading = reading

    return output


def expected_text(lines):
    return "\n".join(gap_fill(lines))


def random_sensor(rng):
    alphabet = string.ascii_letters + string.digits + "-_"
    return "S" + "".join(rng.choice(alphabet) for _ in range(rng.randint(5, 15)))


def make_clean_lines(rng, count=None):
    count = count or rng.randint(3, 8)
    ts = rng.randint(1000, 50000)
    lines = []
    for _ in range(count):
        sensor = random_sensor(rng)
        reading = str(rng.randint(-99, 9999))
        assert len(reading) <= 8
        lines.append(f"{ts},{sensor},{reading}")
        ts += rng.randint(1, 4)
    return lines


def write_lines(path, lines):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def test_scripts_exist_and_are_bash_syntax():
    for path in (FILTER, BATCH):
        assert os.path.exists(path), f"Script not found at {path}"
        assert os.path.isfile(path), f"{path} must be a regular file"
        assert os.access(path, os.R_OK), f"{path} must be readable"
        syntax = run(["bash", "-n", path])
        assert syntax.returncode == 0, f"Invalid Bash syntax in {path}: {syntax.stderr}"


def test_evil_corpus():
    evil_dir = "/opt/verifier/corpora/evil"
    assert os.path.exists(FILTER), f"Sanitizer script not found at {FILTER}"
    assert os.path.isdir(evil_dir), f"Evil corpus directory not found at {evil_dir}"

    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))
    if not evil_files:
        pytest.skip("No evil CSV files found.")

    bypassed = []
    for f in evil_files:
        res = run(["bash", FILTER, f])
        if res.returncode == 0:
            bypassed.append(os.path.basename(f))
        assert res.stdout == "", f"Rejected file {os.path.basename(f)} produced output"

    assert not bypassed, f"{len(bypassed)} of {len(evil_files)} evil bypassed: {', '.join(bypassed)}"


def test_clean_corpus():
    clean_dir = "/opt/verifier/corpora/clean"
    assert os.path.exists(FILTER), f"Sanitizer script not found at {FILTER}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory not found at {clean_dir}"

    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))
    if not clean_files:
        pytest.skip("No clean CSV files found.")

    modified = []
    for f in clean_files:
        with open(f, "r", encoding="utf-8") as infile:
            lines = infile.readlines()
        expected_output = expected_text(lines)
        res = run(["bash", FILTER, f])
        if res.returncode != 0:
            modified.append(f"{os.path.basename(f)} (rejected with exit code {res.returncode})")
        elif res.stdout.strip() != expected_output.strip():
            modified.append(f"{os.path.basename(f)} (output mismatch)")

    assert not modified, f"{len(modified)} of {len(clean_files)} clean modified or failed: {', '.join(modified)}"


def test_randomized_sanitizer_behavior():
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="sanitizer-hidden-") as td:
        for i in range(10):
            lines = make_clean_lines(rng)
            path = os.path.join(td, f"clean-{uuid.uuid4().hex}-{i}.csv")
            write_lines(path, lines)
            res = run(["bash", FILTER, path])
            assert res.returncode == 0, f"Random clean input rejected: {res.stderr}"
            assert res.stdout.strip() == expected_text(lines).strip(), "Incorrect randomized gap-filled output"

        bad_sensors = ["bad;name", "bad&name", "bad$name", "bad name", "bad/name", "bad(name"]
        evil_cases = []
        for sensor in bad_sensors:
            evil_cases.append([f"{rng.randint(100,999)},{sensor},{rng.randint(1,99)}"])
        for _ in range(6):
            prefix = make_clean_lines(rng, 2)
            evil_cases.append(prefix + [f"{rng.randint(50000,60000)},{random_sensor(rng)}," + "7" * rng.randint(9, 30)])

        for i, lines in enumerate(evil_cases):
            path = os.path.join(td, f"evil-{uuid.uuid4().hex}-{i}.csv")
            write_lines(path, lines)
            res = run(["bash", FILTER, path])
            assert res.returncode != 0, "Random malicious input was accepted"
            assert res.stdout == "", "Sanitizer emitted partial output before rejecting a malicious file"


def test_batch_processor_exists():
    assert os.path.exists(BATCH), f"Batch processor script not found at {BATCH}"
    assert os.access(BATCH, os.X_OK) or os.access(BATCH, os.R_OK), f"{BATCH} must be readable/executable"


def test_batch_processing_filtering_outputs_and_parallelism():
    rng = random.SystemRandom()
    with tempfile.TemporaryDirectory(prefix="batch-hidden-") as td:
        input_dir = os.path.join(td, "incoming")
        output_dir = os.path.join(td, "processed")
        state_dir = os.path.join(td, "state")
        os.makedirs(input_dir)
        os.makedirs(state_dir)

        valid = {}
        invalid = []
        for i in range(6):
            name = f"telemetry-{uuid.uuid4().hex}-{i}.csv"
            lines = make_clean_lines(rng, rng.randint(3, 6))
            write_lines(os.path.join(input_dir, name), lines)
            valid[name] = expected_text(lines)

        bad_name = f"telemetry-{uuid.uuid4().hex}-bad-sensor.csv"
        write_lines(os.path.join(input_dir, bad_name), [f"900,bad;{uuid.uuid4().hex[:6]},12"])
        invalid.append(bad_name)
        long_name = f"telemetry-{uuid.uuid4().hex}-bad-reading.csv"
        write_lines(os.path.join(input_dir, long_name), [f"901,{random_sensor(rng)},123456789"])
        invalid.append(long_name)
        with open(os.path.join(input_dir, "ignore.txt"), "w", encoding="utf-8") as f:
            f.write("not a csv\n")

        backup = FILTER + ".verifier-backup-" + uuid.uuid4().hex
        calls = os.path.join(state_dir, "calls")
        overlap = os.path.join(state_dir, "overlap")
        markers = os.path.join(state_dir, "markers")
        os.mkdir(markers)
        os.replace(FILTER, backup)
        try:
            wrapper = f'''#!/bin/bash
printf '%s\\n' "$1" >> {shlex.quote(calls)}
marker={shlex.quote(markers)}/$$
: > "$marker"
sleep 0.20
count=$(find {shlex.quote(markers)} -type f | wc -l)
if [ "$count" -ge 2 ]; then : > {shlex.quote(overlap)}; fi
sleep 0.20
rm -f "$marker"
exec bash {shlex.quote(backup)} "$@"
'''
            with open(FILTER, "w", encoding="utf-8", newline="\n") as f:
                f.write(wrapper)
            os.chmod(FILTER, 0o755)

            res = run(["bash", BATCH, input_dir, output_dir], cwd="/home/user")
            assert res.returncode == 0, f"Batch processor failed: {res.stderr}"

            assert os.path.isdir(output_dir), "Batch processor did not create the output directory"
            actual_files = sorted(os.path.basename(p) for p in glob.glob(os.path.join(output_dir, "*")))
            assert actual_files == sorted(valid), "Batch output files do not exactly match accepted CSV inputs"

            for name, expected in valid.items():
                path = os.path.join(output_dir, name)
                assert os.path.isfile(path), f"Missing output for valid file {name}"
                with open(path, "r", encoding="utf-8") as f:
                    actual = f.read()
                assert actual.strip() == expected.strip(), f"Incorrect batch output for {name}"

            for name in invalid:
                assert not os.path.exists(os.path.join(output_dir, name)), f"Invalid file {name} produced an output"

            assert os.path.exists(calls), "Batch processor did not invoke filter_and_fill.sh"
            with open(calls, "r", encoding="utf-8") as f:
                called = [os.path.basename(line.strip()) for line in f if line.strip()]
            expected_calls = sorted(valid.keys() | set(invalid))
            assert sorted(called) == expected_calls, "Batch processor did not sanitize every and only .csv input"
            assert os.path.exists(overlap), "CSV files were not processed in parallel"
        finally:
            try:
                if os.path.exists(FILTER):
                    os.unlink(FILTER)
            finally:
                if os.path.exists(backup):
                    os.replace(backup, FILTER)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
