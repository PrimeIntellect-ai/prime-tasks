#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shlex
import signal
import stat
import subprocess
import time
import pytest

HOME = "/home/user"


def is_executable(path):
    return os.path.isfile(path) and os.access(path, os.X_OK)


def test_init_storage_sh():
    script_path = "/home/user/init_storage.sh"
    assert is_executable(script_path), f"{script_path} must exist and be executable."

    subprocess.run(["rm", "-rf", "/home/user/app_data"], check=True)
    result = subprocess.run([script_path], capture_output=True)
    assert result.returncode == 0, f"{script_path} must exit with code 0."

    assert os.path.isdir("/home/user/app_data"), "/home/user/app_data must be created."
    quota_file = "/home/user/app_data/quota_config"
    assert os.path.isfile(quota_file), f"{quota_file} must be created."

    with open(quota_file, "r") as f:
        content = f.read().strip()
    assert content == "QUOTA=8192", f"{quota_file} must contain 'QUOTA=8192'."

    with open(quota_file, "w") as f:
        f.write("QUOTA=9999")

    result2 = subprocess.run([script_path], capture_output=True)
    assert result2.returncode == 0, f"{script_path} must exit with code 0 on second run."

    with open(quota_file, "r") as f:
        content2 = f.read().strip()
    assert content2 == "QUOTA=9999", f"{script_path} must not overwrite {quota_file} if it already exists."

    with open(quota_file, "w") as f:
        f.write("QUOTA=8192")


def test_start_services_sh():
    script_path = "/home/user/start_services.sh"
    supervisor_path = "/home/user/supervisor"
    assert is_executable(script_path), f"{script_path} must exist and be executable."
    assert os.path.isfile(supervisor_path), f"{supervisor_path} must exist."

    with open(supervisor_path, "rb") as f:
        original_supervisor = f.read()
    original_mode = stat.S_IMODE(os.stat(supervisor_path).st_mode)

    token = random.SystemRandom().randrange(10**10, 10**12)
    marker = f"/tmp/start_services_marker_{token}"
    stub = f'''#!/bin/sh
{{
  printf '%s:' "$$"
  if [ -f /home/user/app_data/quota_config ]; then
    cat /home/user/app_data/quota_config
  else
    printf 'MISSING'
  fi
  printf '\\n'
}} > {shlex.quote(marker)}
sleep 10
'''

    subprocess.run(["rm", "-rf", "/home/user/app_data"], check=True)
    timed_out = False
    result = None
    observed = None
    child_pid = None
    try:
        with open(supervisor_path, "w") as f:
            f.write(stub)
        os.chmod(supervisor_path, 0o755)

        try:
            result = subprocess.run(
                [script_path], cwd=HOME,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                timeout=2
            )
        except subprocess.TimeoutExpired:
            timed_out = True

        deadline = time.time() + 1
        while not os.path.exists(marker) and time.time() < deadline:
            time.sleep(0.02)
        if os.path.exists(marker):
            with open(marker, "r") as f:
                observed = f.read().strip()
            try:
                child_pid = int(observed.split(":", 1)[0])
            except (ValueError, IndexError):
                child_pid = None
    finally:
        with open(supervisor_path, "wb") as f:
            f.write(original_supervisor)
        os.chmod(supervisor_path, original_mode)
        if child_pid is not None:
            try:
                os.kill(child_pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass

    assert not timed_out, "start_services.sh must launch supervisor in the background and return promptly."
    assert result is not None and result.returncode == 0, "start_services.sh must exit with code 0."
    assert observed is not None, "start_services.sh must execute ./supervisor."
    assert observed.split(":", 1)[1] == "QUOTA=8192", "init_storage.sh must complete before supervisor is launched."


def test_supervisor_c_fixes():
    c_file = "/home/user/supervisor.c"
    assert os.path.isfile(c_file), f"{c_file} must exist."

    with open(c_file, "r") as f:
        content = f.read()

    assert "NULL" in content or "!" in content, "supervisor.c must check if fopen returned NULL."
    assert "sscanf" in content or "atoi" in content or "strtol" in content, "supervisor.c must parse the quota value."


def test_supervisor_compiled_and_safe():
    exe_path = "/home/user/supervisor"
    assert is_executable(exe_path), f"{exe_path} must be compiled and executable."
    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{exe_path} must be a compiled executable."

    subprocess.run(["rm", "-f", "/home/user/app_data/quota_config"], check=True)
    result = subprocess.run([exe_path], capture_output=True, timeout=3)
    assert result.returncode != 139, f"{exe_path} must not segfault when quota_config is missing."
    assert result.returncode != 0, f"{exe_path} should exit with non-zero status when config is missing."
    assert result.returncode > 0, f"{exe_path} must exit normally rather than crash when config is missing."

    subprocess.run(["/home/user/init_storage.sh"], check=True)


def test_supervisor_parses_runtime_quota():
    exe_path = "/home/user/supervisor"
    worker_path = "/home/user/worker.sh"
    quota_path = "/home/user/app_data/quota_config"
    quota = random.SystemRandom().randrange(20000, 90000)

    with open(worker_path, "rb") as f:
        original_worker = f.read()
    original_mode = stat.S_IMODE(os.stat(worker_path).st_mode)

    try:
        with open(worker_path, "w") as f:
            f.write("#!/bin/sh\nexit 0\n")
        os.chmod(worker_path, 0o755)
        os.makedirs("/home/user/app_data", exist_ok=True)
        with open(quota_path, "w") as f:
            f.write(f"QUOTA={quota}\n")

        result = subprocess.run([exe_path], capture_output=True, text=True, timeout=3)
        assert result.returncode == 0, "supervisor must run successfully with a valid quota configuration."
        assert re.search(rf"(?<!\\d){quota}(?!\\d)", result.stdout), "supervisor must parse and use the quota from the configuration file."
    finally:
        with open(worker_path, "wb") as f:
            f.write(original_worker)
        os.chmod(worker_path, original_mode)
        with open(quota_path, "w") as f:
            f.write("QUOTA=8192")


def test_parse_metrics_sh():
    script_path = "/home/user/parse_metrics.sh"
    assert is_executable(script_path), f"{script_path} must exist and be executable."


def test_critical_sum_txt():
    sum_file = "/home/user/critical_sum.txt"
    assert os.path.isfile(sum_file), f"{sum_file} must exist."

    with open(sum_file, "r") as f:
        content = f.read().strip()

    assert content == "520", f"{sum_file} must contain the sum '520'."


def test_parse_metrics_behavior_on_derived_input():
    script_path = "/home/user/parse_metrics.sh"
    metrics_path = "/home/user/app_data/metrics.log"
    sum_path = "/home/user/critical_sum.txt"
    rng = random.SystemRandom()
    values = [rng.randrange(11, 900), rng.randrange(901, 1800), rng.randrange(1801, 3000)]
    expected = sum(values)

    os.makedirs("/home/user/app_data", exist_ok=True)
    with open(metrics_path, "w") as f:
        f.write("2026-01-01T00:00:00 INFO 999 ignored\n")
        f.write(f"2026-01-01T00:00:01 CRITICAL {values[0]} first\n")
        f.write("2026-01-01T00:00:02 CRITICALITY 700 ignored-near-match\n")
        f.write(f"2026-01-01T00:00:03 CRITICAL {values[1]} second\n")
        f.write("2026-01-01T00:00:04 WARNING 500 ignored\n")
        f.write(f"2026-01-01T00:00:05 CRITICAL {values[2]} third\n")

    result = subprocess.run([script_path], cwd=HOME, capture_output=True, timeout=3)
    assert result.returncode == 0, "parse_metrics.sh must execute successfully."
    assert os.path.isfile(sum_path), "parse_metrics.sh must write /home/user/critical_sum.txt."
    with open(sum_path, "r") as f:
        output = f.read().strip()
    assert re.fullmatch(r"[+-]?\d+", output), "critical_sum.txt must contain a single integer."
    assert int(output) == expected, "parse_metrics.sh must sum only the third column of exact CRITICAL-level lines."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
