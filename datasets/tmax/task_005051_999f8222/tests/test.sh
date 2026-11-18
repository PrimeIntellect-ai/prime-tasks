#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import fcntl
import json
import os
import shutil
import subprocess
import tempfile
import time
import uuid
import pytest


def run_rejected(argv):
    try:
        result = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    except subprocess.TimeoutExpired:
        pytest.fail(f"Invalid invocation did not terminate: {argv}")
    assert result.returncode != 0, f"Invalid invocation was accepted: {argv}"


def blocks(data, size=64):
    assert len(data) % size == 0, f"Database length {len(data)} is not a multiple of {size}"
    return sorted(data[i:i + size] for i in range(0, len(data), size))


def test_deploy_script_and_speedup():
    script_path = "/home/user/deploy.sh"
    input_file = "/home/user/incoming/routes.txt"
    compiler_path = "/app/mlist_compiler"
    release_id = "test_run_01"

    assert os.path.exists(script_path), f"Deployment script missing at {script_path}"
    assert os.access(script_path, os.X_OK), f"Deployment script is not executable: {script_path}"

    current_link = "/home/user/deployments/current"
    previous_link = "/home/user/deployments/previous"
    release_dir = f"/home/user/deployments/releases/{release_id}"
    agent_db = f"{release_dir}/routes.db"

    old_current_target = os.readlink(current_link) if os.path.islink(current_link) else None

    # The script must reject every argument count other than exactly two.
    run_rejected([script_path])
    run_rejected([script_path, "invalid_one_arg"])
    run_rejected([script_path, "invalid_three_args", input_file, "extra"])

    if old_current_target is not None:
        assert os.path.islink(current_link), "Invalid invocations changed current into a non-symlink"
        assert os.readlink(current_link) == old_current_target, "Invalid invocations changed current"

    # Build the sequential reference, retain it only in verifier memory, and remove
    # its filesystem artifact before the deployment script is invoked.
    ref_fd, ref_path = tempfile.mkstemp(prefix="mlist-reference-", suffix=".db")
    os.close(ref_fd)
    start_time = time.time()
    try:
        result = subprocess.run(
            [compiler_path, input_file, ref_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
        t_ref = time.time() - start_time
        with open(ref_path, "rb") as f:
            ref_data = f.read()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Reference compiler failed: {e.stderr.decode('utf-8', errors='ignore')}")
    finally:
        if os.path.exists(ref_path):
            os.unlink(ref_path)

    # Replace the public compiler path temporarily with an instrumented delegating
    # wrapper. It records compiler inputs/outputs and actual overlapping calls.
    trace_dir = tempfile.mkdtemp(prefix="mlist-trace-")
    os.chmod(trace_dir, 0o700)
    real_compiler = f"/app/.mlist_compiler.verifier-{uuid.uuid4().hex}"
    os.replace(compiler_path, real_compiler)

    wrapper_code = "#!/usr/bin/python3\nREAL = " + repr(real_compiler) + "\nTRACE = " + repr(trace_dir) + "\n" + r'''
import fcntl
import json
import os
import shutil
import subprocess
import sys
import time
import uuid

lock_path = os.path.join(TRACE, "lock")
state_path = os.path.join(TRACE, "state")
log_path = os.path.join(TRACE, "calls.jsonl")
call_id = f"{os.getpid()}-{uuid.uuid4().hex}"
input_snapshot = os.path.join(TRACE, call_id + ".input")
output_snapshot = os.path.join(TRACE, call_id + ".output")
started = time.monotonic()

with open(lock_path, "a+") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    active = maximum = 0
    if os.path.exists(state_path):
        text = open(state_path).read().strip()
        if text:
            active, maximum = map(int, text.split())
    active += 1
    maximum = max(maximum, active)
    with open(state_path, "w") as state:
        state.write(f"{active} {maximum}\n")

snap_error = None
if len(sys.argv) == 3:
    try:
        shutil.copyfile(sys.argv[1], input_snapshot)
    except Exception as exc:
        snap_error = repr(exc)

try:
    proc = subprocess.run([REAL] + sys.argv[1:])
    returncode = proc.returncode
except Exception as exc:
    returncode = 127
    snap_error = (snap_error or "") + repr(exc)

if len(sys.argv) == 3 and os.path.isfile(sys.argv[2]):
    try:
        shutil.copyfile(sys.argv[2], output_snapshot)
    except Exception as exc:
        snap_error = (snap_error or "") + repr(exc)

ended = time.monotonic()
record = {
    "id": call_id,
    "argv": sys.argv[1:],
    "returncode": returncode,
    "input_snapshot": input_snapshot if os.path.isfile(input_snapshot) else None,
    "output_snapshot": output_snapshot if os.path.isfile(output_snapshot) else None,
    "started": started,
    "ended": ended,
    "snapshot_error": snap_error,
}

with open(lock_path, "a+") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    active = maximum = 0
    if os.path.exists(state_path):
        text = open(state_path).read().strip()
        if text:
            active, maximum = map(int, text.split())
    active -= 1
    with open(state_path, "w") as state:
        state.write(f"{active} {maximum}\n")
    with open(log_path, "a") as log:
        log.write(json.dumps(record) + "\n")

sys.exit(returncode)
'''

    with open(compiler_path, "w") as f:
        f.write(wrapper_code)
    os.chmod(compiler_path, 0o755)

    if os.path.lexists(release_dir):
        if os.path.isdir(release_dir) and not os.path.islink(release_dir):
            shutil.rmtree(release_dir)
        else:
            os.unlink(release_dir)

    start_time = time.time()
    try:
        try:
            result = subprocess.run(
                [script_path, release_id, input_file],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
                timeout=120,
            )
            t_agent = time.time() - start_time
        except subprocess.TimeoutExpired:
            pytest.fail("Agent script timed out")
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script failed: {e.stderr.decode('utf-8', errors='ignore')}")
    finally:
        # Restore the proprietary compiler even when the deployment test fails.
        if os.path.lexists(compiler_path):
            os.unlink(compiler_path)
        os.replace(real_compiler, compiler_path)

    speedup = t_ref / t_agent

    # Preserve the original rolling-deployment assertions.
    assert os.path.islink(current_link), f"{current_link} is not a symlink"
    new_current_target = os.readlink(current_link)
    expected_current_target = release_dir
    assert new_current_target == expected_current_target, (
        f"Expected current symlink to point to {expected_current_target}, got {new_current_target}"
    )

    if old_current_target is not None:
        assert os.path.islink(previous_link), f"{previous_link} is not a symlink"
        new_previous_target = os.readlink(previous_link)
        assert new_previous_target == old_current_target, (
            f"Expected previous symlink to point to {old_current_target}, got {new_previous_target}"
        )

    assert os.path.isdir(release_dir), f"Release directory missing at {release_dir}"
    assert os.path.exists(agent_db), f"Output database missing at {agent_db}"
    with open(agent_db, "rb") as f:
        agent_data = f.read()

    assert len(ref_data) == len(agent_data), (
        f"Database size mismatch: expected {len(ref_data)} bytes, got {len(agent_data)} bytes"
    )
    assert blocks(ref_data) == blocks(agent_data), "Database content mismatch after sorting 64-byte records"

    # Confirm the real compiler was called on a complete partition of the input,
    # with multiple compiler processes genuinely overlapping.
    log_path = os.path.join(trace_dir, "calls.jsonl")
    assert os.path.isfile(log_path), "No compiler invocations were recorded"
    with open(log_path) as f:
        calls = [json.loads(line) for line in f if line.strip()]

    assert len(calls) >= 2, f"Expected multiple chunk compiler invocations, observed {len(calls)}"
    assert all(len(call["argv"]) == 2 for call in calls), "Compiler was invoked with an invalid argument count"
    assert all(call["returncode"] == 0 for call in calls), "At least one compiler invocation failed"
    assert all(call["snapshot_error"] is None for call in calls), "Could not inspect compiler inputs or outputs"

    state_path = os.path.join(trace_dir, "state")
    assert os.path.isfile(state_path), "Compiler concurrency state was not recorded"
    active, maximum = map(int, open(state_path).read().split())
    assert active == 0, "Compiler wrapper was still active after deployment"
    assert maximum >= 2, f"Compiler calls did not run in parallel (maximum concurrency was {maximum})"

    with open(input_file, "rb") as f:
        original_lines = f.read().splitlines(keepends=True)
    compiled_lines = []
    compiled_outputs = bytearray()
    for call in calls:
        assert call["input_snapshot"] and os.path.isfile(call["input_snapshot"]), "Missing chunk snapshot"
        assert call["output_snapshot"] and os.path.isfile(call["output_snapshot"]), "Missing compiler output snapshot"
        with open(call["input_snapshot"], "rb") as f:
            chunk_lines = f.read().splitlines(keepends=True)
        assert chunk_lines, "An empty chunk was passed to the compiler"
        assert len(chunk_lines) < len(original_lines), "The full input was passed as a single chunk"
        compiled_lines.extend(chunk_lines)
        with open(call["output_snapshot"], "rb") as f:
            compiled_outputs.extend(f.read())

    assert collections.Counter(compiled_lines) == collections.Counter(original_lines), (
        "Compiler chunk inputs do not form a complete partition of the requested input"
    )
    assert blocks(bytes(compiled_outputs)) == blocks(agent_data), (
        "Final database was not composed from the recorded compiler outputs"
    )

    # Preserve the original performance requirement.
    assert speedup >= 2.8, (
        f"Speedup too low: {speedup:.2f} (T_ref={t_ref:.2f}s, T_agent={t_agent:.2f}s). "
        "Expected speedup >= 2.8"
    )


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-x", "--tb=short"]))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
