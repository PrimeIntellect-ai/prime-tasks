#!/bin/bash
set +e
mkdir -p /logs/verifier

verify_submission() {
    local launcher=/tmp/run_and_monitor.py
    local hash_marker=/tmp/verifier_hash_used
    local parallel_marker=/tmp/verifier_parallel_used
    local clean_file=/home/user/clean_configs.jsonl
    local candidate
    local passed=0

    cat <<'PY_EOF' > "$launcher"
import hashlib
import multiprocessing
import multiprocessing.pool
import os
import runpy
import sys
from concurrent.futures import ProcessPoolExecutor

script, hash_marker, parallel_marker = sys.argv[1:4]

def mark(path):
    try:
        with open(path, "ab", buffering=0) as f:
            f.write(b"1\n")
    except OSError:
        pass

_original_sha256 = hashlib.sha256
def monitored_sha256(*args, **kwargs):
    mark(hash_marker)
    return _original_sha256(*args, **kwargs)
hashlib.sha256 = monitored_sha256

_original_new = hashlib.new
def monitored_new(name, *args, **kwargs):
    if str(name).lower().replace("-", "") == "sha256":
        mark(hash_marker)
    return _original_new(name, *args, **kwargs)
hashlib.new = monitored_new

# Mark actual submission of work to a process executor.
_original_executor_submit = ProcessPoolExecutor.submit
def monitored_executor_submit(self, *args, **kwargs):
    mark(parallel_marker)
    return _original_executor_submit(self, *args, **kwargs)
ProcessPoolExecutor.submit = monitored_executor_submit

# Mark actual dispatch through multiprocessing.Pool APIs.
def monitor_pool_method(name):
    original = getattr(multiprocessing.pool.Pool, name)
    def monitored(self, *args, **kwargs):
        mark(parallel_marker)
        return original(self, *args, **kwargs)
    setattr(multiprocessing.pool.Pool, name, monitored)

for method_name in (
    "apply", "apply_async", "map", "map_async", "starmap", "starmap_async",
    "imap", "imap_unordered"
):
    monitor_pool_method(method_name)

# Also support programs that explicitly create and start Process objects.
_original_process_start = multiprocessing.process.BaseProcess.start
def monitored_process_start(self, *args, **kwargs):
    mark(parallel_marker)
    return _original_process_start(self, *args, **kwargs)
multiprocessing.process.BaseProcess.start = monitored_process_start

sys.argv = [script]
os.chdir(os.path.dirname(script) or ".")
runpy.run_path(script, run_name="__main__")
PY_EOF

    mapfile -d '' candidates < <(find /home/user -type f -name '*.py' -print0 2>/dev/null)
    if [ "${#candidates[@]}" -eq 0 ]; then
        echo "No Python script was written under /home/user." >&2
        return 1
    fi

    for candidate in "${candidates[@]}"; do
        # Avoid executing unrelated Python files; a qualifying implementation must
        # contain both SHA-256 and process-parallelism APIs.
        if ! grep -Eqi 'sha-?256|sha256' "$candidate"; then
            continue
        fi
        if ! grep -Eq 'multiprocessing|ProcessPoolExecutor' "$candidate"; then
            continue
        fi
        if ! python3 -m py_compile "$candidate" >/dev/null 2>&1; then
            continue
        fi

        rm -f "$clean_file" "$hash_marker" "$parallel_marker"
        if timeout 180s python3 "$launcher" "$candidate" "$hash_marker" "$parallel_marker" >/tmp/verifier_script_stdout 2>/tmp/verifier_script_stderr; then
            if [ -s "$clean_file" ] && [ -s "$hash_marker" ] && [ -s "$parallel_marker" ]; then
                passed=1
                break
            fi
        fi
    done

    if [ "$passed" -ne 1 ]; then
        echo "No Python script both generated the output and dynamically used SHA-256 plus process-based parallel work." >&2
        return 1
    fi

    cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

RAW_FILE = "/home/user/raw_configs.jsonl"
CLEAN_FILE = "/home/user/clean_configs.jsonl"

def test_clean_configs_exists():
    """Verify that the clean configuration output file exists."""
    assert os.path.exists(CLEAN_FILE), f"Output file {CLEAN_FILE} does not exist."
    assert os.path.isfile(CLEAN_FILE), f"{CLEAN_FILE} is not a file."
    assert os.path.getsize(CLEAN_FILE) > 0, f"{CLEAN_FILE} is empty."

def test_unicode_unescaped():
    """Verify that Unicode characters are not escaped in the output file."""
    with open(CLEAN_FILE, "r", encoding="utf-8") as f:
        content = f.read()

    # If ensure_ascii=True was used, we would see \uXXXX instead of actual characters
    # We know the input has characters like Веб-сервер, 缓存, قاعدة البيانات
    assert "Веб-сервер" in content or "缓存" in content or "قاعدة البيانات" in content, \
        "Output file does not contain literal Unicode characters. Did you use ensure_ascii=False?"

def test_output_correctness_and_sorting():
    """Verify the deduplication, filtering, and sorting logic against the raw file."""
    assert os.path.exists(RAW_FILE), f"{RAW_FILE} is missing, cannot verify."

    # 1. Compute expected truth
    records = []
    with open(RAW_FILE, "r", encoding="utf-8") as f:
        for line in f:
            records.append(json.loads(line))

    valid = [r for r in records if r.get("config_data", {}).get("app_name") is not None]

    dedup = {}
    for r in valid:
        cd_str = json.dumps(r["config_data"], sort_keys=True, separators=(',', ':'), ensure_ascii=False)
        key = r["server_id"] + "||" + cd_str

        if key not in dedup:
            dedup[key] = r
        else:
            if r["timestamp"] < dedup[key]["timestamp"]:
                dedup[key] = r

    expected_records = list(dedup.values())
    expected_records.sort(key=lambda x: (x["server_id"], x["timestamp"]))

    # 2. Read actual output
    actual_records = []
    with open(CLEAN_FILE, "r", encoding="utf-8") as f:
        for i, line in enumerate(f):
            try:
                actual_records.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Line {i+1} in {CLEAN_FILE} is not valid JSON.")

    # 3. Compare lengths
    assert len(actual_records) == len(expected_records), \
        f"Expected {len(expected_records)} records, but found {len(actual_records)}."

    # 4. Compare records and their order
    for i, (actual, expected) in enumerate(zip(actual_records, expected_records)):
        assert actual == expected, \
            f"Record mismatch at line {i+1}.\nExpected: {expected}\nActual: {actual}\n" \
            "Make sure records are deduplicated correctly (minimum timestamp) and sorted by server_id then timestamp."

    # 5. Check validation checkpoint explicitly on actual records
    for i, r in enumerate(actual_records):
        config_data = r.get("config_data", {})
        assert "app_name" in config_data, f"Record at line {i+1} is missing 'app_name' in 'config_data'."
        assert config_data["app_name"] is not None, f"Record at line {i+1} has null 'app_name'."
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short
}

if verify_submission 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
