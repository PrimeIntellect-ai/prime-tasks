#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import signal
import subprocess
import time

SRC = "/home/user/src/metric_exporter.c"
BIN = "/home/user/bin/metric_exporter"
MGR = "/home/user/service_mgr.sh"
DEPLOY = "/home/user/deploy.sh"


def wait_for(predicate, timeout=5.0, interval=0.05, message="condition was not met"):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(interval)
    assert predicate(), message


def metric_path(instance):
    return f"/home/user/metrics_{instance}.prom"


def expected_metric(instance):
    return f'dashboard_metric{{instance="{instance}"}} 100\n'


def read_file(path):
    with open(path, "r") as f:
        return f.read()


def run_must_exit(argv, timeout=2):
    try:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as exc:
        if exc.process:
            exc.process.kill()
        raise AssertionError(f"Command did not reject invalid arguments: {argv}")
    assert result.returncode != 0, f"Command unexpectedly accepted invalid arguments: {argv}"


def test_files_exist_and_permissions():
    assert os.path.isfile(SRC), "metric_exporter.c is missing."
    assert os.path.isfile(MGR), "service_mgr.sh is missing."
    assert os.path.isfile(DEPLOY), "deploy.sh is missing."
    assert os.access(MGR, os.X_OK), "service_mgr.sh is not executable."
    assert os.access(DEPLOY, os.X_OK), "deploy.sh is not executable."


def test_deployment_and_metrics():
    # Add an unpredictable, retained object to the submitted C translation unit.
    # Its presence in the deployed ELF demonstrates that deploy.sh actually built
    # the submitted source rather than installing a pre-created executable.
    marker = "VERIFIER_BUILD_" + secrets.token_hex(20)
    with open(SRC, "rb") as f:
        original_source = f.read()
    source_addition = (
        f'\n__attribute__((used,retain)) volatile const char '
        f'verifier_build_marker_{secrets.token_hex(8)}[] = "{marker}";\n'
    ).encode()

    original_mgr = MGR + ".verifier_original"
    call_log = "/tmp/service_calls_" + secrets.token_hex(8)
    os.replace(MGR, original_mgr)
    wrapper = f'''#!/bin/bash
printf '%s %s\\n' "$1" "$2" >> {call_log}
if [ "$1" = restart ] && [ "$2" = 2 ]; then
    [ -f /home/user/metrics_1.prom ] || exit 91
    grep -Fxq 'dashboard_metric{{instance="1"}} 100' /home/user/metrics_1.prom || exit 92
fi
exec {original_mgr} "$@"
'''
    with open(MGR, "w") as f:
        f.write(wrapper)
    os.chmod(MGR, 0o755)
    with open(SRC, "ab") as f:
        f.write(source_addition)

    try:
        result = subprocess.run([DEPLOY], capture_output=True, text=True, timeout=30)
    finally:
        with open(SRC, "wb") as f:
            f.write(original_source)
        if os.path.exists(original_mgr):
            os.replace(original_mgr, MGR)

    assert result.returncode == 0, (
        f"deploy.sh failed with return code {result.returncode}\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )

    assert os.path.isfile(BIN), "Binary metric_exporter was not compiled to /home/user/bin/."
    assert os.access(BIN, os.X_OK), "Binary metric_exporter is not executable."
    with open(BIN, "rb") as f:
        binary_data = f.read()
    assert binary_data.startswith(b"\x7fELF"), "metric_exporter is not a compiled ELF executable."
    assert marker.encode() in binary_data, "The deployed binary was not compiled from metric_exporter.c."

    # The source itself must remain compilable as C.
    compile_result = subprocess.run(
        ["gcc", SRC, "-o", "/tmp/verifier_source_build"],
        capture_output=True, text=True
    )
    assert compile_result.returncode == 0, f"metric_exporter.c does not compile: {compile_result.stderr}"

    calls = read_file(call_log).splitlines() if os.path.exists(call_log) else []
    assert "restart 1" in calls, "deploy.sh did not use service_mgr.sh to restart instance 1."
    assert "restart 2" in calls, "deploy.sh did not use service_mgr.sh to restart instance 2."
    assert calls.index("restart 1") < calls.index("restart 2"), "Instances were not rolled in order."

    assert os.path.isfile("/home/user/deploy.log"), "deploy.log is missing."
    with open("/home/user/deploy.log", "r") as f:
        log_content = f.read()
    assert "ROLLING_DEPLOY_SUCCESS" in log_content, "deploy.log does not contain 'ROLLING_DEPLOY_SUCCESS'."

    metrics_files = {1: metric_path(1), 2: metric_path(2)}
    for instance, file_path in metrics_files.items():
        assert os.path.isfile(file_path), f"Metrics file {file_path} is missing."
        content = read_file(file_path).strip()
        expected = f'dashboard_metric{{instance="{instance}"}} 100'
        assert content == expected, f"Metrics file {file_path} content mismatch. Expected '{expected}', got '{content}'."

    # The exporter must accept exactly one integer argument and reject all other forms.
    invalid_id = "invalid_" + secrets.token_hex(4)
    run_must_exit([BIN])
    run_must_exit([BIN, "7", "extra"])
    run_must_exit([BIN, invalid_id])
    assert not os.path.exists(metric_path(invalid_id)), "Invalid instance_id created a metric file."

    # Exercise an unpredictable instance directly. Verify looping, roughly one-second
    # sleeping, exact overwrite behavior, and exporter-owned SIGTERM cleanup/exit 0.
    direct_id = 10000 + secrets.randbelow(80000)
    direct_metric = metric_path(direct_id)
    try:
        os.unlink(direct_metric)
    except FileNotFoundError:
        pass
    proc = subprocess.Popen([BIN, str(direct_id)])
    try:
        wait_for(lambda: os.path.isfile(direct_metric), message="Exporter did not create its metric file.")
        assert read_file(direct_metric) == expected_metric(direct_id), "Random instance payload is incorrect."
        assert proc.poll() is None, "Exporter did not remain running continuously."

        first_mtime = os.stat(direct_metric).st_mtime_ns
        wait_for(
            lambda: os.path.exists(direct_metric) and os.stat(direct_metric).st_mtime_ns != first_mtime,
            timeout=2.5,
            message="Exporter did not perform another loop iteration."
        )
        with open(direct_metric, "w") as f:
            f.write("corrupted\n")
        time.sleep(0.30)
        assert read_file(direct_metric) == "corrupted\n", "Exporter is not sleeping between iterations."
        wait_for(
            lambda: os.path.exists(direct_metric) and read_file(direct_metric) == expected_metric(direct_id),
            timeout=1.5,
            message="Exporter did not overwrite the metric on its next iteration."
        )

        proc.send_signal(signal.SIGTERM)
        returncode = proc.wait(timeout=4)
        assert returncode == 0, f"Exporter did not exit gracefully on SIGTERM (code {returncode})."
        assert not os.path.exists(direct_metric), "Exporter itself did not delete its metric file on SIGTERM."
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        try:
            os.unlink(direct_metric)
        except FileNotFoundError:
            pass

    # The manager must itself enforce its two-argument interface.
    run_must_exit([MGR])
    run_must_exit([MGR, "start"])
    run_must_exit([MGR, "start", "3", "extra"])
    run_must_exit([MGR, "unsupported", "3"])

    # Exercise start, restart, and stop through the submitted manager on another
    # unpredictable instance and verify that pidfiles refer to real exporters.
    managed_id = 100000 + secrets.randbelow(80000)
    managed_metric = metric_path(managed_id)
    pidfile = f"/home/user/run/metric_exporter_{managed_id}.pid"
    start = subprocess.run([MGR, "start", str(managed_id)], capture_output=True, text=True, timeout=5)
    assert start.returncode == 0, f"service_mgr.sh start failed: {start.stderr}"
    wait_for(lambda: os.path.isfile(pidfile) and os.path.isfile(managed_metric), message="Managed exporter did not start.")
    old_pid = int(read_file(pidfile).strip())
    cmdline = open(f"/proc/{old_pid}/cmdline", "rb").read().split(b"\0")
    assert os.path.realpath(os.fsdecode(cmdline[0])) == os.path.realpath(BIN), "Pidfile does not identify metric_exporter."
    assert os.fsdecode(cmdline[1]) == str(managed_id), "Managed exporter has the wrong instance argument."
    assert read_file(managed_metric) == expected_metric(managed_id), "Managed random metric payload is incorrect."

    restart = subprocess.run([MGR, "restart", str(managed_id)], capture_output=True, text=True, timeout=8)
    assert restart.returncode == 0, f"service_mgr.sh restart failed: {restart.stderr}"
    wait_for(lambda: os.path.isfile(pidfile) and os.path.isfile(managed_metric), message="Managed exporter did not restart.")
    new_pid = int(read_file(pidfile).strip())
    assert new_pid != old_pid, "restart did not replace the exporter process."
    assert not os.path.exists(f"/proc/{old_pid}"), "restart returned before the old exporter exited."

    stop = subprocess.run([MGR, "stop", str(managed_id)], capture_output=True, text=True, timeout=8)
    assert stop.returncode == 0, "service_mgr.sh stop for random instance failed."
    assert not os.path.exists(pidfile), "Random instance pidfile was not deleted after stop."
    assert not os.path.exists(managed_metric), "Random instance metric was not deleted after stop."
    assert not os.path.exists(f"/proc/{new_pid}"), "stop returned before the exporter exited."

    # Preserve the original checks for deployed instances and final process cleanup.
    for instance in [1, 2]:
        stop_result = subprocess.run([MGR, "stop", str(instance)], capture_output=True, text=True, timeout=8)
        assert stop_result.returncode == 0, f"service_mgr.sh stop {instance} failed."

    time.sleep(1)
    for instance, file_path in metrics_files.items():
        assert not os.path.exists(file_path), f"Metrics file {file_path} was not deleted after SIGTERM."
        deployed_pidfile = f"/home/user/run/metric_exporter_{instance}.pid"
        assert not os.path.exists(deployed_pidfile), f"PID file {deployed_pidfile} was not deleted after stop."

    pgrep_result = subprocess.run(["pgrep", "-f", "metric_exporter"], capture_output=True, text=True)
    assert pgrep_result.returncode != 0, "metric_exporter processes are still running after stop."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
