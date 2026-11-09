#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import subprocess
import time
import pytest

def test_health_check_exists_and_executable():
    """Test that health_check.sh exists and is executable."""
    path = "/home/user/health_check.sh"
    assert os.path.isfile(path), f"{path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"{path} is not executable."

def test_service_and_health_check_behavior():
    """Test live-PID, stale-PID, and health-check behavior."""
    pid_file = "/home/user/service/run/service.pid"
    status_file = "/home/user/service/data/status.txt"
    start_script = "/home/user/service/start_service.sh"
    health_script = "/home/user/health_check.sh"

    # 1. Verify initial health check (service should be running and healthy)
    result = subprocess.run(["bash", health_script], capture_output=True, text=True)
    assert result.returncode == 0, f"health_check.sh exited with code {result.returncode}, expected 0."
    assert result.stdout.strip() == "HEALTHY", f"health_check.sh output was '{result.stdout.strip()}', expected 'HEALTHY'."

    assert os.path.isfile(pid_file), f"PID file {pid_file} is missing."
    with open(pid_file, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file does not contain a valid integer: {pid_str}"
    pid = int(pid_str)

    # 2. A duplicate start while the recorded process is live must be rejected.
    try:
        duplicate = subprocess.run(
            ["bash", start_script], capture_output=True, text=True, timeout=2
        )
    except subprocess.TimeoutExpired:
        pytest.fail("start_service.sh did not reject a duplicate start while the service was running.")
    assert duplicate.returncode == 1, f"Duplicate start exited with {duplicate.returncode}, expected 1."
    assert "Service already running" in duplicate.stdout, (
        f"Duplicate start output was '{duplicate.stdout.strip()}', expected 'Service already running'."
    )
    with open(pid_file, "r") as f:
        assert f.read().strip() == pid_str, "Duplicate start overwrote the live service PID file."

    # 3. ACTIVE alone is insufficient: invalid and dead PIDs must be unhealthy.
    with open(status_file, "w") as f:
        f.write("ACTIVE\n")
    with open(pid_file, "w") as f:
        f.write("not-a-pid\n")
    invalid_result = subprocess.run(["bash", health_script], capture_output=True, text=True)
    assert invalid_result.returncode == 1, f"health_check.sh should exit with 1 for an invalid PID, got {invalid_result.returncode}."
    assert invalid_result.stdout.strip() == "UNHEALTHY", f"health_check.sh should output UNHEALTHY for an invalid PID, got '{invalid_result.stdout.strip()}'."

    exited = subprocess.Popen(["/bin/true"])
    dead_pid = exited.pid
    exited.wait()
    with open(pid_file, "w") as f:
        f.write(f"{dead_pid}\n")
    dead_result = subprocess.run(["bash", health_script], capture_output=True, text=True)
    assert dead_result.returncode == 1, f"health_check.sh should exit with 1 for a dead PID, got {dead_result.returncode}."
    assert dead_result.stdout.strip() == "UNHEALTHY", f"health_check.sh should output UNHEALTHY for a dead PID, got '{dead_result.stdout.strip()}'."

    # Restore the live service PID before testing stale PID recovery.
    with open(pid_file, "w") as f:
        f.write(f"{pid}\n")
    restored = subprocess.run(["bash", health_script], capture_output=True, text=True)
    assert restored.returncode == 0, "Service was not healthy after restoring its live PID."
    assert restored.stdout.strip() == "HEALTHY", "Health check did not report HEALTHY after restoring the live PID."

    # 4. Test stale lock handling.
    try:
        os.kill(pid, 9)
    except ProcessLookupError:
        pass

    time.sleep(0.5)

    # Start the service again in the background.
    proc = subprocess.Popen(["bash", start_script])
    time.sleep(1)

    # Check health again to ensure it successfully handled the stale PID.
    result2 = subprocess.run(["bash", health_script], capture_output=True, text=True)
    assert result2.returncode == 0, "Service failed to start or health_check failed after stale PID recovery."
    assert result2.stdout.strip() == "HEALTHY", "Service is not HEALTHY after recovering from stale PID."

    # 5. Check health_check.sh failure mode for a non-ACTIVE status.
    with open(status_file, "w") as f:
        f.write("INACTIVE\n")

    result3 = subprocess.run(["bash", health_script], capture_output=True, text=True)
    assert result3.returncode == 1, f"health_check.sh should exit with 1 when status is not ACTIVE, got {result3.returncode}."
    assert result3.stdout.strip() == "UNHEALTHY", f"health_check.sh should output UNHEALTHY, got '{result3.stdout.strip()}'."

    # Cleanup: kill the process we spawned during the test.
    try:
        with open(pid_file, "r") as f:
            new_pid = int(f.read().strip())
        os.kill(new_pid, 9)
    except Exception:
        pass
    if proc.poll() is None:
        proc.kill()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
