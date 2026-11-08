#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess
import tempfile


def expected_worker_output(values, threshold):
    return [
        (f"CRITICAL: Value {value} exceeds threshold" if value > threshold
         else f"INFO: Value {value} is normal")
        for value in values
    ]


def run_worker(binary, values, threshold):
    metrics_path = "/home/user/metrics.dat"
    with open(metrics_path, "w") as f:
        f.write("".join(f"{value}\n" for value in values))

    env = os.environ.copy()
    if threshold is None:
        env.pop("ALERT_THRESHOLD", None)
        expected_threshold = 80
    else:
        env["ALERT_THRESHOLD"] = str(threshold)
        expected_threshold = threshold

    result = subprocess.run(
        [binary], env=env, text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0, (
        f"{binary} failed with code {result.returncode}: {result.stderr}"
    )
    assert result.stdout.strip().splitlines() == expected_worker_output(
        values, expected_threshold
    )


def test_alerts_log_content():
    path = "/home/user/alerts.log"
    assert os.path.isfile(path), f"Missing file: {path}"

    expected_lines = [
        "[ALERT] Value 90 exceeds threshold",
        "[ALERT] Value 95 exceeds threshold",
        "[ALERT] Value 100 exceeds threshold",
        "[ALERT] Value 86 exceeds threshold"
    ]

    with open(path, "r") as f:
        content = f.read().strip().splitlines()

    assert content == expected_lines, f"Content of {path} does not match the expected output. Got: {content}"


def test_bashrc_contains_export():
    path = "/home/user/.bashrc"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "r") as f:
        content = f.read()

    assert "export ALERT_THRESHOLD=85" in content, f"{path} does not contain 'export ALERT_THRESHOLD=85'"


def test_worker_binary_executable():
    path = "/home/user/worker"
    assert os.path.isfile(path), f"Missing compiled binary: {path}"

    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Binary {path} is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{path} is not a compiled ELF binary"


def test_run_monitor_sh_executable():
    path = "/home/user/run_monitor.sh"
    assert os.path.isfile(path), f"Missing script: {path}"

    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {path} is not executable"


def test_worker_c_uses_getenv():
    path = "/home/user/worker.c"
    assert os.path.isfile(path), f"Missing file: {path}"

    with open(path, "r") as f:
        content = f.read()

    assert "getenv" in content, f"{path} does not appear to use getenv() to read the environment variable."


def test_source_and_binary_implement_dynamic_threshold():
    metrics_path = "/home/user/metrics.dat"
    with open(metrics_path, "rb") as f:
        original_metrics = f.read()

    rebuilt = "/tmp/worker_rebuilt"
    try:
        compile_result = subprocess.run(
            ["gcc", "/home/user/worker.c", "-o", rebuilt],
            text=True, capture_output=True, timeout=20
        )
        assert compile_result.returncode == 0, (
            f"worker.c does not compile: {compile_result.stderr}"
        )

        threshold = 120 + secrets.randbelow(500)
        dynamic_values = [threshold - 7, threshold, threshold + 1,
                          threshold + 11 + secrets.randbelow(50)]
        default_values = [79, 80, 81, 90 + secrets.randbelow(100)]

        for binary in ("/home/user/worker", rebuilt):
            run_worker(binary, dynamic_values, threshold)
            run_worker(binary, default_values, None)
    finally:
        with open(metrics_path, "wb") as f:
            f.write(original_metrics)
        if os.path.exists(rebuilt):
            os.unlink(rebuilt)


def test_monitor_script_contains_required_pipeline_elements():
    path = "/home/user/run_monitor.sh"
    with open(path, "r") as f:
        content = f.read()

    assert "/home/user/worker" in content, "run_monitor.sh does not invoke /home/user/worker"
    assert ".bashrc" in content and re.search(
        r"(^|[;\n])\s*(source|\.)\s+[^\n]*\.bashrc", content
    ), "run_monitor.sh does not source .bashrc"
    assert "|" in content, "run_monitor.sh does not pipe the worker output"
    assert re.search(r"\b(grep|awk|sed)\b", content), (
        "run_monitor.sh does not use grep, awk, or sed"
    )
    assert "/home/user/alerts.log" in content, (
        "run_monitor.sh does not write /home/user/alerts.log"
    )


def test_monitor_executes_real_worker_end_to_end():
    alerts_path = "/home/user/alerts.log"
    if os.path.exists(alerts_path):
        os.unlink(alerts_path)

    env = os.environ.copy()
    env.pop("ALERT_THRESHOLD", None)
    result = subprocess.run(
        ["/home/user/run_monitor.sh"], env=env,
        text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0, (
        f"run_monitor.sh failed with code {result.returncode}: {result.stderr}"
    )
    assert os.path.isfile(alerts_path), "run_monitor.sh did not create alerts.log"
    with open(alerts_path, "r") as f:
        actual = f.read().strip().splitlines()
    assert actual == [
        "[ALERT] Value 90 exceeds threshold",
        "[ALERT] Value 95 exceeds threshold",
        "[ALERT] Value 100 exceeds threshold",
        "[ALERT] Value 86 exceeds threshold",
    ]


def test_monitor_sources_environment_runs_worker_and_transforms_output():
    worker_path = "/home/user/worker"
    alerts_path = "/home/user/alerts.log"
    token = secrets.token_hex(12)

    with open(worker_path, "rb") as f:
        original_worker = f.read()
    original_mode = stat.S_IMODE(os.stat(worker_path).st_mode)
    original_alerts = None
    if os.path.exists(alerts_path):
        with open(alerts_path, "rb") as f:
            original_alerts = f.read()

    probe = f'''#!/bin/sh
[ "${{ALERT_THRESHOLD-}}" = "85" ] || exit 42
printf '%s\\n' \\
  'INFO: ignore-{token}' \\
  'CRITICAL: first-{token}' \\
  'NOTCRITICAL: ignore-{token}' \\
  'CRITICAL: second-{token}'
'''

    try:
        with open(worker_path, "w") as f:
            f.write(probe)
        os.chmod(worker_path, 0o755)
        if os.path.exists(alerts_path):
            os.unlink(alerts_path)

        env = os.environ.copy()
        env.pop("ALERT_THRESHOLD", None)
        result = subprocess.run(
            ["/home/user/run_monitor.sh"], env=env,
            text=True, capture_output=True, timeout=10
        )
        assert result.returncode == 0, (
            "run_monitor.sh did not source ALERT_THRESHOLD=85 and execute "
            f"/home/user/worker: {result.stderr}"
        )
        assert os.path.isfile(alerts_path), "run_monitor.sh did not create alerts.log"
        with open(alerts_path, "r") as f:
            actual = f.read().strip().splitlines()
        assert actual == [f"[ALERT] first-{token}", f"[ALERT] second-{token}"], (
            f"run_monitor.sh did not correctly filter and reformat worker output: {actual}"
        )
    finally:
        with open(worker_path, "wb") as f:
            f.write(original_worker)
        os.chmod(worker_path, original_mode)
        if original_alerts is None:
            if os.path.exists(alerts_path):
                os.unlink(alerts_path)
        else:
            with open(alerts_path, "wb") as f:
                f.write(original_alerts)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
