#!/bin/bash
set -e
mkdir -p /logs/verifier
pkill -x aggregator 2>/dev/null || true
rm -f /tmp/aggregator-source-check

cat <<'PY_EOF' > /tmp/test_aggregator.py
import fcntl
import os
import random
import signal
import subprocess
import time
import uuid

HOME = "/home/user"
INCOMING = HOME + "/incoming_data"
LOG = HOME + "/processed_sums.log"
SOURCE = HOME + "/aggregator.go"
BINARY = HOME + "/aggregator"
BUILT = "/tmp/aggregator-source-check"
UID = 1000
GID = 1000


def clean_state():
    os.makedirs(INCOMING, exist_ok=True)
    for name in os.listdir(INCOMING):
        path = os.path.join(INCOMING, name)
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)
    try:
        os.unlink(LOG)
    except FileNotFoundError:
        pass


def start(binary):
    proc = subprocess.Popen(
        ["runuser", "-u", "user", "--", binary],
        cwd=HOME,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    time.sleep(0.8)
    assert proc.poll() is None, f"{binary} exited instead of continuously watching"
    return proc


def stop(proc):
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            proc.wait(timeout=3)


def lines():
    if not os.path.exists(LOG):
        return []
    with open(LOG, encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def wait_for(predicate, timeout=8, message="condition was not met"):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return
        time.sleep(0.1)
    raise AssertionError(message)


def make_file(name, values, mode=0o600):
    temp = os.path.join(HOME, ".verifier-" + uuid.uuid4().hex)
    with open(temp, "w", encoding="utf-8") as f:
        for value in values:
            f.write(f"{value}\n")
        f.flush()
        os.fsync(f.fileno())
    os.chown(temp, UID, GID)
    os.chmod(temp, mode)
    destination = os.path.join(INCOMING, name)
    os.rename(temp, destination)
    return destination


# Preserve the original artifact assertions and ensure the source is real Go code.
assert os.path.exists(SOURCE), f"Go source file {SOURCE} does not exist."
assert os.path.exists(BINARY), f"Go compiled binary {BINARY} does not exist."
assert os.access(BINARY, os.X_OK), f"Go binary {BINARY} is not executable."
assert os.path.exists(os.path.join(HOME, "go.mod")), "The required Go module was not initialized."
with open(SOURCE, encoding="utf-8") as f:
    source_text = f.read()
assert "syscall.Flock" in source_text, "aggregator.go must use syscall.Flock"
assert "LOCK_EX" in source_text and "LOCK_NB" in source_text, "The flock call must request LOCK_EX|LOCK_NB"
metadata = subprocess.run(["go", "version", "-m", BINARY], text=True, capture_output=True)
assert metadata.returncode == 0 and "go1." in (metadata.stdout + metadata.stderr), "aggregator is not a compiled Go executable"
build = subprocess.run(
    ["go", "build", "-o", BUILT, "./aggregator.go"],
    cwd=HOME,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    timeout=90,
)
assert build.returncode == 0, "aggregator.go does not build:\n" + build.stdout

# Execute the submitted binary with the supplied simulator, retaining the original
# exact output and cleanup checks.
clean_state()
proc = start(BINARY)
try:
    simulation = subprocess.run(
        ["runuser", "-u", "user", "--", HOME + "/simulator.sh"],
        cwd=HOME,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=25,
    )
    assert simulation.returncode == 0, simulation.stdout
    expected_original = {"batch_1.csv:50", "batch_2.csv:95", "batch_3.csv:80"}
    wait_for(
        lambda: set(lines()) == expected_original and not [n for n in os.listdir(INCOMING) if n.endswith(".csv")],
        timeout=10,
        message=f"Simulator files were not correctly processed; log contains {lines()}",
    )
    assert os.path.exists(LOG), f"Log file {LOG} does not exist."
    assert set(lines()) == expected_original, f"Log file contents do not match expected sums: {lines()}"
    csv_files = [n for n in os.listdir(INCOMING) if n.endswith(".csv")]
    assert len(csv_files) == 0, f"Incoming directory still contains CSV files: {csv_files}"
finally:
    stop(proc)

# Execute a fresh build of the submitted source against randomized inputs. This
# checks continuous watching, executable-bit filtering, nonblocking lock behavior,
# derived sums, output naming, and deletion without trusting fixed answers.
clean_state()
proc = start(BUILT)
locked_handle = None
try:
    rng = random.SystemRandom()
    token = uuid.uuid4().hex

    exec_name = f"exec_{token}.csv"
    exec_values = [rng.randint(-5000, 5000) for _ in range(4)]
    exec_path = make_file(exec_name, exec_values[:2], 0o700)
    with open(exec_path, "a", encoding="utf-8") as f:
        for value in exec_values[2:]:
            f.write(f"{value}\n")
        f.flush()
        os.fsync(f.fileno())
    time.sleep(1.5)
    assert os.path.exists(exec_path), "An owner-executable CSV was processed before finalization"
    assert not any(line.startswith(exec_name + ":") for line in lines()), "Executable CSV was logged"

    locked_name = f"locked_{token}.csv"
    locked_values = [rng.randint(-9000, 9000) for _ in range(5)]
    locked_path = make_file(locked_name, locked_values, 0o600)
    locked_handle = open(locked_path, "r")
    fcntl.flock(locked_handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    # Generate another event after the lock is already held.
    os.utime(locked_path, None)

    free_name = f"free_{token}.csv"
    free_values = [rng.randint(-9000, 9000) for _ in range(6)]
    free_path = make_file(free_name, free_values, 0o600)
    free_line = f"{free_name}:{sum(free_values)}"
    wait_for(
        lambda: free_line in lines() and not os.path.exists(free_path),
        timeout=5,
        message="A locked file blocked processing of a later unlocked file; flock may be blocking",
    )
    assert os.path.exists(locked_path), "A CSV was processed despite another process holding an exclusive lock"
    assert not any(line.startswith(locked_name + ":") for line in lines()), "Locked CSV was logged"

    # Finalizing the executable file must trigger later processing in the same process.
    os.chmod(exec_path, 0o600)
    exec_line = f"{exec_name}:{sum(exec_values)}"
    wait_for(
        lambda: exec_line in lines() and not os.path.exists(exec_path),
        timeout=7,
        message="CSV was not processed after its owner executable bit was removed",
    )
    assert proc.poll() is None, "Watcher stopped instead of processing continuously"

    fcntl.flock(locked_handle.fileno(), fcntl.LOCK_UN)
    locked_handle.close()
    locked_handle = None
    os.utime(locked_path, None)
    locked_line = f"{locked_name}:{sum(locked_values)}"
    wait_for(
        lambda: locked_line in lines() and not os.path.exists(locked_path),
        timeout=7,
        message="Previously locked CSV was not retried and processed after lock release",
    )

    note_name = f"keep_{token}.txt"
    note_path = make_file(note_name, [123], 0o600)
    time.sleep(1)
    assert os.path.exists(note_path), "A non-CSV file was incorrectly deleted"

    expected_dynamic = {free_line, exec_line, locked_line}
    assert set(lines()) == expected_dynamic, f"Unexpected or incorrect dynamic log lines: {lines()}"
    csv_files = [n for n in os.listdir(INCOMING) if n.endswith(".csv")]
    assert csv_files == [], f"Successfully processed CSV files were not deleted: {csv_files}"
finally:
    if locked_handle is not None:
        try:
            fcntl.flock(locked_handle.fileno(), fcntl.LOCK_UN)
            locked_handle.close()
        except Exception:
            pass
    stop(proc)
PY_EOF

if python3 /tmp/test_aggregator.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
