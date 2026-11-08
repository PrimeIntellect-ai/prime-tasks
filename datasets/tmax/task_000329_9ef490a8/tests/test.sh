#!/bin/bash
mkdir -p /logs/verifier

REAL_BIN=/tmp/legacy_aggregator.real
MARKER=/tmp/legacy_invocations.log
rm -f "$MARKER" /tmp/legacy_capture.*

restore_legacy() {
    if [ -f "$REAL_BIN" ]; then
        rm -f /app/legacy_aggregator
        mv "$REAL_BIN" /app/legacy_aggregator
    fi
}
trap restore_legacy EXIT

if [ ! -x /app/legacy_aggregator ] || ! mv /app/legacy_aggregator "$REAL_BIN"; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'SHIM_EOF' > /app/legacy_aggregator
#!/bin/bash
capture=$(mktemp /tmp/legacy_capture.XXXXXX) || exit 1
cat > "$capture" || exit 1
printf '%s\n' "$capture" >> /tmp/legacy_invocations.log
exec /tmp/legacy_aggregator.real < "$capture"
SHIM_EOF
chmod 755 /app/legacy_aggregator
: > "$MARKER"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import random
import re
import subprocess
import tempfile
from collections import Counter

import pytest

CSV_PATH = "/home/user/reconstructed_inputs.csv"
SCRIPT_PATH = "/home/user/safe_aggregator.sh"
REAL_BIN = "/tmp/legacy_aggregator.real"
MARKER = "/tmp/legacy_invocations.log"
LOG_PATHS = [
    "/data/gateway.log",
    "/data/queue.log",
    "/data/aggregator_node.log",
]
LINE_RE = re.compile(
    r"^(?P<timestamp>\d+(?:\.\d+)?) \[(?P<tx>[^\]]+)\] "
    r"PAYLOAD_CHUNK: (?P<value>\S+)\s*$"
)
NUMBER_RE = re.compile(
    r"[+-]?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+))(?:[eE][+-]?\d+)?"
)


def expected_reconstruction():
    records = {}
    for log_path in LOG_PATHS:
        with open(log_path, encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, 1):
                match = LINE_RE.match(line)
                assert match, f"Malformed source log line {log_path}:{line_number}: {line!r}"
                tx = match.group("tx")
                timestamp = float(match.group("timestamp"))
                value = float(match.group("value"))
                assert math.isfinite(value)
                records.setdefault(tx, []).append((timestamp, value))
    return {
        tx: [value for timestamp, value in sorted(entries, key=lambda item: item[0])]
        for tx, entries in records.items()
    }


def read_submission_csv():
    rows = {}
    with open(CSV_PATH, newline="", encoding="utf-8") as handle:
        for line_number, row in enumerate(csv.reader(handle), 1):
            assert row, f"Blank row at line {line_number}"
            assert len(row) >= 2, f"Row {line_number} has no numeric payloads"
            tx = row[0].strip()
            assert tx and tx not in rows, f"Missing or duplicate transaction ID {tx!r}"
            try:
                values = [float(field.strip()) for field in row[1:]]
            except ValueError as exc:
                pytest.fail(f"Non-numeric value in CSV row {line_number}: {exc}")
            assert all(math.isfinite(value) for value in values)
            rows[tx] = values
    return rows


def marker_entries():
    if not os.path.exists(MARKER):
        return []
    with open(MARKER, encoding="utf-8") as handle:
        return [line.strip() for line in handle if line.strip()]


def parse_single_number(stdout):
    text = stdout.strip()
    assert NUMBER_RE.fullmatch(text), f"Output was not exactly one finite number: {stdout!r}"
    value = float(text)
    assert math.isfinite(value), f"Output was not finite: {stdout!r}"
    return value


def same_numeric_sequence_as_multiset(left, right):
    if len(left) != len(right):
        return False
    left = sorted(left)
    right = sorted(right)
    return all(math.isclose(a, b, rel_tol=1e-7, abs_tol=1e-12) for a, b in zip(left, right))


def run_wrapper(values, filename=None):
    if filename is None:
        fd, filename = tempfile.mkstemp(prefix="held_out_", suffix=".txt")
        os.close(fd)
    with open(filename, "w", encoding="utf-8") as handle:
        for value in values:
            handle.write(f"{value}\n")

    before = len(marker_entries())
    result = subprocess.run(
        [SCRIPT_PATH, filename], capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"
    )
    agent_sum = parse_single_number(result.stdout)

    new_captures = marker_entries()[before:]
    assert new_captures, "The wrapper did not invoke /app/legacy_aggregator"

    matching_capture = None
    matching_legacy_output = None
    for capture_path in new_captures:
        assert os.path.isfile(capture_path), f"Missing captured legacy input {capture_path}"
        with open(capture_path, encoding="utf-8") as handle:
            try:
                captured_values = [float(line.strip()) for line in handle if line.strip()]
            except ValueError:
                continue
        if not same_numeric_sequence_as_multiset(captured_values, values):
            continue
        legacy = subprocess.run(
            [REAL_BIN],
            input="".join(f"{value}\n" for value in captured_values),
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert legacy.returncode == 0
        legacy_sum = parse_single_number(legacy.stdout)
        if math.isclose(agent_sum, legacy_sum, rel_tol=0.0, abs_tol=1e-6):
            matching_capture = capture_path
            matching_legacy_output = legacy_sum
            break

    assert matching_capture is not None, (
        "The wrapper must pipe all input values into /app/legacy_aggregator and output "
        "that invocation's result"
    )
    return agent_sum, matching_legacy_output


def test_reconstructed_inputs_exists():
    path = CSV_PATH
    assert os.path.exists(path), f"Missing reconstructed inputs file at {path}"
    assert os.path.isfile(path), f"{path} is not a file"
    assert os.path.getsize(path) > 0, f"{path} is empty"


def test_reconstructed_inputs_match_logs_and_timeline():
    expected = expected_reconstruction()
    submitted = read_submission_csv()
    assert set(submitted) == set(expected), (
        f"Expected exactly transactions {sorted(expected)}, got {sorted(submitted)}"
    )
    for tx, expected_values in expected.items():
        actual_values = submitted[tx]
        assert len(actual_values) == len(expected_values), (
            f"Transaction {tx} has {len(actual_values)} values; expected {len(expected_values)}"
        )
        for index, (actual, wanted) in enumerate(zip(actual_values, expected_values)):
            assert actual == wanted, (
                f"Transaction {tx} value {index} is {actual}, expected {wanted} "
                "from timestamp ordering across the logs"
            )


def test_safe_aggregator_exists_and_executable():
    path = SCRIPT_PATH
    assert os.path.exists(path), f"Missing safe aggregator script at {path}"
    assert os.path.isfile(path), f"{path} is not a file"
    assert os.access(path, os.X_OK), f"Safe aggregator script at {path} is not executable"


def test_safe_aggregator_accuracy():
    # Preserve the original held-out accuracy assertion.
    vals = [10000000.0] + [0.015] * 50000
    random.SystemRandom().shuffle(vals)
    agent_sum, _ = run_wrapper(vals, "/tmp/held_out.txt")
    true_sum = sum(vals)
    absolute_error = abs(true_sum - agent_sum)
    assert absolute_error < 50.0, (
        f"Absolute error {absolute_error} is too high! Expected < 50.0. "
        f"True sum: {true_sum}, Agent sum: {agent_sum}. "
        "Did you sort the values by magnitude before summing?"
    )


def test_safe_aggregator_on_unpredictable_skewed_inputs():
    rng = random.SystemRandom()
    small_choices = [0.011, 0.013, 0.017, 0.019, 0.023, 0.029]
    for case_number in range(4):
        count = rng.randint(18000, 28000)
        small_values = [rng.choice(small_choices) for _ in range(count)]
        rng.shuffle(small_values)
        large = rng.choice([8000000.0, 10000000.0, 14000000.0, 20000000.0])
        # Keep the large term near the start so unprocessed float32 accumulation
        # reliably loses many later small terms, while all details remain random.
        position = rng.randint(0, max(1, count // 20))
        vals = small_values[:position] + [large] + small_values[position:]

        agent_sum, _ = run_wrapper(vals)
        true_sum = math.fsum(vals)
        absolute_error = abs(true_sum - agent_sum)
        assert absolute_error < 50.0, (
            f"Dynamic case {case_number} had absolute error {absolute_error}; "
            f"expected < 50.0 (baseline {true_sum}, output {agent_sum})"
        )


def test_reconstructed_data_serves_as_mre():
    reconstructed = read_submission_csv()
    for tx, vals in reconstructed.items():
        raw = subprocess.run(
            [REAL_BIN],
            input="".join(f"{value}\n" for value in vals),
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert raw.returncode == 0
        raw_sum = parse_single_number(raw.stdout)
        safe_sum, _ = run_wrapper(vals)
        baseline = math.fsum(vals)
        assert abs(safe_sum - baseline) <= abs(raw_sum - baseline) + 1e-6, (
            f"For reconstructed transaction {tx}, the wrapper made the legacy "
            "floating-point error worse"
        )
        assert abs(safe_sum - baseline) < 50.0
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    result=1
else
    result=0
fi

restore_legacy
trap - EXIT
echo "$result" > /logs/verifier/reward.txt
