#!/bin/bash
set -u
mkdir -p /logs/verifier

APP_DIR=/home/user/telemetry_app
MAIN_RS="$APP_DIR/src/main.rs"
TMPDIR=$(mktemp -d)
BIN="$TMPDIR/telemetry_app"
cp "$APP_DIR/input_logs.txt" "$TMPDIR/original_input_logs.txt"

cleanup() {
    cp "$TMPDIR/original_input_logs.txt" "$APP_DIR/input_logs.txt" 2>/dev/null || true
    if [ -f "$TMPDIR/original_corrected_metrics.txt" ]; then
        cp "$TMPDIR/original_corrected_metrics.txt" "$APP_DIR/corrected_metrics.txt" 2>/dev/null || true
    fi
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

run_checks() {
    # Compile src/main.rs directly so the restored source itself must be a valid executable.
    test -f "$MAIN_RS" || return 1
    rustc --edition=2021 "$MAIN_RS" -o "$BIN" || return 1
    test -x "$BIN" || return 1

    # Execute it on the task's original input before retaining the original assertions.
    (cd "$APP_DIR" && "$BIN") || return 1

    cat << 'TEST_EOF' > "$TMPDIR/test_final_state.py"
import os

def test_main_rs_restored():
    main_rs_path = "/home/user/telemetry_app/src/main.rs"
    assert os.path.isfile(main_rs_path), f"The source code file {main_rs_path} was not restored."

def test_corrected_metrics_output():
    output_file = "/home/user/telemetry_app/corrected_metrics.txt"
    assert os.path.isfile(output_file), f"The output file {output_file} was not generated."

    with open(output_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = [
        "4125000000",
        "4125000000",
        "3750000000",
        "3925000000",
        "5050000000",
        "6150000000"
    ]

    assert len(lines) == len(expected), f"Expected {len(expected)} lines in {output_file}, but got {len(lines)}."

    for i, (actual, exp) in enumerate(zip(lines, expected)):
        assert actual == exp, f"Line {i+1} in {output_file} is incorrect. Expected {exp}, got {actual}."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$TMPDIR/test_final_state.py" -x --tb=short || return 1
    cp "$APP_DIR/corrected_metrics.txt" "$TMPDIR/original_corrected_metrics.txt" || return 1

    # Exercise the compiled program on unpredictable inputs. Expected answers are
    # independently derived here rather than taken from a submitted output file.
    python3 - "$BIN" "$APP_DIR" << 'PY_EOF'
import os
import re
import secrets
import subprocess
import sys

binary, app_dir = sys.argv[1:]
input_path = os.path.join(app_dir, "input_logs.txt")
output_path = os.path.join(app_dir, "corrected_metrics.txt")
rng = secrets.SystemRandom()

cases = [
    [rng.randint(700_000_000, 900_000_000) for _ in range(5)],
    [rng.randint(1, 1_000_000) for _ in range(6)],
    [rng.randint(10_000, 900_000_000) for _ in range(10)],
    [rng.randint(50_000, 500_000_000) for _ in range(13)],
]

for case_num, values in enumerate(cases, 1):
    expected = [sum(v * v for v in values[i:i + 5])
                for i in range(len(values) - 5 + 1)]
    with open(input_path, "w", encoding="utf-8") as f:
        f.write("\n".join(map(str, values)) + "\n")

    if os.path.exists(output_path):
        os.remove(output_path)
    result = subprocess.run([binary], cwd=app_dir, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert result.returncode == 0, (
        f"Program failed on behavioral case {case_num}: {result.stderr}")
    assert os.path.isfile(output_path), (
        f"Program did not create corrected_metrics.txt on case {case_num}")

    with open(output_path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()
    assert all(re.fullmatch(r"-?\d+", line) for line in lines), (
        f"Case {case_num} output must contain exactly one integer per line: {lines!r}")
    actual = [int(line) for line in lines]
    assert actual == expected, (
        f"Behavioral case {case_num} incorrect. Expected {expected}, got {actual}")
PY_EOF
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
