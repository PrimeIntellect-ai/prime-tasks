#!/bin/bash
set -u
mkdir -p /logs/verifier

TRACE_DIR="$(mktemp -d /tmp/migrate-verifier.XXXXXX)"
REAL_TIME="$TRACE_DIR/real-time"
TIME_PATH="/usr/bin/time"

restore_time() {
    if [ -e "$REAL_TIME" ]; then
        rm -f "$TIME_PATH"
        mv "$REAL_TIME" "$TIME_PATH"
    fi
}
trap restore_time EXIT

# Use data different from the image's fixed fixture, and remove any pre-created results.
cat > /home/user/artifacts/registry.csv <<'CSV_EOF'
id,timestamp,size_bytes,filename
verify-a,1800000001,1572864,alpha-build.tar.gz
verify-b,1800000002,50000000,beta-symbols.zip
verify-c,1800000003,104857600,gamma-release.bin
verify-d,1800000004,0,empty-verification.log
CSV_EOF
rm -f /home/user/artifacts/new_registry.json /home/user/artifacts/benchmark.log

# Instrument the required absolute time binary. The wrapper runs the genuine binary,
# records its arguments, and snapshots the timing output before migrate.sh can alter it.
mv "$TIME_PATH" "$REAL_TIME"
export VERIFIER_REAL_TIME="$REAL_TIME"
export VERIFIER_TRACE_DIR="$TRACE_DIR"
cat > "$TIME_PATH" <<'WRAPPER_EOF'
#!/bin/bash
printf '%s\0' "$@" > "$VERIFIER_TRACE_DIR/args"
printf '1\n' > "$VERIFIER_TRACE_DIR/invoked"

output_file=""
previous=""
for argument in "$@"; do
    if [ "$previous" = "-o" ] || [ "$previous" = "--output" ]; then
        output_file="$argument"
    fi
    case "$argument" in
        --output=*) output_file="${argument#--output=}" ;;
        -o?*) output_file="${argument#-o}" ;;
    esac
    previous="$argument"
done

stderr_capture="$VERIFIER_TRACE_DIR/time.stderr"
"$VERIFIER_REAL_TIME" "$@" 2>"$stderr_capture"
status=$?
cp "$stderr_capture" "$VERIFIER_TRACE_DIR/captured.stderr"
cat "$stderr_capture" >&2

if [ -n "$output_file" ] && [ -f "$output_file" ]; then
    cp "$output_file" "$VERIFIER_TRACE_DIR/captured.output"
    printf '%s\n' "$output_file" > "$VERIFIER_TRACE_DIR/output.path"
fi
exit "$status"
WRAPPER_EOF
chmod 755 "$TIME_PATH"

if [ -x /home/user/migrate.sh ]; then
    /home/user/migrate.sh
    printf '%s\n' "$?" > "$TRACE_DIR/script.status"
else
    printf '126\n' > "$TRACE_DIR/script.status"
fi

restore_time
trap - EXIT

export MIGRATE_TRACE_DIR="$TRACE_DIR"
cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import re
import pytest

TRACE_DIR = os.environ["MIGRATE_TRACE_DIR"]


def test_script_executable():
    """Verify that the migration script exists and is executable and ran successfully."""
    script_path = "/home/user/migrate.sh"
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."
    with open(os.path.join(TRACE_DIR, "script.status"), "r") as f:
        assert f.read().strip() == "0", "Migration script did not exit successfully."


def test_json_output_correctness():
    """Verify that the JSON output is correctly derived from the verification CSV."""
    csv_path = "/home/user/artifacts/registry.csv"
    json_path = "/home/user/artifacts/new_registry.json"

    assert os.path.isfile(csv_path), f"Original CSV file {csv_path} is missing."
    assert os.path.isfile(json_path), f"JSON output file {json_path} is missing."

    numeric_tokens = []

    def capture_float(token):
        numeric_tokens.append(token)
        return float(token)

    with open(json_path, "r") as f:
        try:
            actual_json = json.load(f, parse_float=capture_float)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {json_path} is not valid JSON.")

    assert isinstance(actual_json, list), "JSON output must be an array of objects."

    expected_json = []
    with open(csv_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            size_bytes = int(row["size_bytes"])
            size_mb_raw = size_bytes / 1048576.0
            size_mb = float(f"{size_mb_raw:.2f}")
            storage_index = math.ceil(math.sqrt(size_mb) * 1.5)
            expected_json.append({
                "id": row["id"],
                "filename": row["filename"],
                "size_mb": size_mb,
                "storage_index": storage_index,
            })

    assert len(actual_json) == len(expected_json), "JSON array length does not match CSV row count."

    for actual, expected in zip(actual_json, expected_json):
        assert actual.get("id") == expected["id"], f"Expected id '{expected['id']}', got '{actual.get('id')}'"
        assert actual.get("filename") == expected["filename"], f"Expected filename '{expected['filename']}', got '{actual.get('filename')}'"

        actual_size_mb = actual.get("size_mb")
        assert actual_size_mb is not None, "Missing 'size_mb' field in JSON object."
        assert not isinstance(actual_size_mb, bool) and isinstance(actual_size_mb, float), \
            "size_mb must be a JSON floating-point number."
        assert math.isclose(actual_size_mb, expected["size_mb"], rel_tol=1e-5), \
            f"Expected size_mb {expected['size_mb']} for {expected['id']}, got {actual_size_mb}"

        actual_storage_index = actual.get("storage_index")
        assert actual_storage_index is not None, "Missing 'storage_index' field in JSON object."
        assert actual_storage_index == expected["storage_index"], \
            f"Expected storage_index {expected['storage_index']} for {expected['id']}, got {actual_storage_index}"

    assert len(numeric_tokens) == len(expected_json), \
        "Each size_mb value must be represented as a JSON floating-point number."
    for token in numeric_tokens:
        assert re.fullmatch(r"-?\d+\.\d{2}", token), \
            f"size_mb value '{token}' is not formatted with exactly two decimal places."


def test_benchmark_log():
    """Verify that genuine /usr/bin/time user-CPU output produced the benchmark log."""
    log_path = "/home/user/artifacts/benchmark.log"
    assert os.path.isfile(log_path), f"Benchmark log {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content, "Benchmark log is empty."
    assert re.fullmatch(r"(?:\d+(?:\.\d*)?|\.\d+)", content), \
        f"Benchmark log does not contain only a numeric value. Found: '{content}'"
    assert float(content) >= 0, "CPU time in benchmark log cannot be negative."

    assert os.path.isfile(os.path.join(TRACE_DIR, "invoked")), \
        "The script did not execute the required /usr/bin/time command."
    with open(os.path.join(TRACE_DIR, "args"), "rb") as f:
        args = [part.decode() for part in f.read().split(b"\0") if part]

    has_user_format = any(arg == "%U" and i > 0 and args[i - 1] in ("-f", "--format")
                          for i, arg in enumerate(args))
    has_user_format |= any(arg == "--format=%U" for arg in args)
    assert has_user_format, "/usr/bin/time must be invoked with the user CPU format string %U."

    captured_candidates = []
    for name in ("captured.output", "captured.stderr"):
        path = os.path.join(TRACE_DIR, name)
        if os.path.isfile(path):
            with open(path, "r") as f:
                value = f.read().strip()
            if re.fullmatch(r"(?:\d+(?:\.\d*)?|\.\d+)", value):
                captured_candidates.append(value)

    assert content in captured_candidates, \
        "benchmark.log was not populated from the output produced by /usr/bin/time."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
rm -rf "$TRACE_DIR"
