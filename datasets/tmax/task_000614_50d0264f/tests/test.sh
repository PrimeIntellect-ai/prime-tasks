#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tempfile


def test_bashrc_contains_env_var():
    """Verify that EDGE_NODE_ID=IOT-992 is in /home/user/.bashrc."""
    bashrc_path = "/home/user/.bashrc"
    assert os.path.isfile(bashrc_path), f"{bashrc_path} does not exist or is not a file."

    with open(bashrc_path, "r") as f:
        content = f.read()

    assert "EDGE_NODE_ID=IOT-992" in content, "EDGE_NODE_ID=IOT-992 not found in /home/user/.bashrc."


def test_iot_config_ini():
    """Verify /home/user/iot_config.ini exists and has correct values."""
    config_path = "/home/user/iot_config.ini"
    assert os.path.isfile(config_path), f"{config_path} does not exist or is not a file."

    with open(config_path, "r") as f:
        content = f.read()

    assert re.search(r"AdminEmail\s*=\s*ops@edge\.local", content), "AdminEmail=ops@edge.local not found in iot_config.ini."
    assert re.search(r"SpoolDir\s*=\s*/home/user/mail_spool/outbox", content), "SpoolDir=/home/user/mail_spool/outbox not found in iot_config.ini."


def test_monitor_cpp_and_executable_exist():
    """Verify the monitor.cpp and compiled monitor executable exist."""
    cpp_path = "/home/user/monitor.cpp"
    exe_path = "/home/user/monitor"

    assert os.path.isfile(cpp_path), f"{cpp_path} does not exist."
    assert os.path.isfile(exe_path), f"{exe_path} does not exist."
    assert os.access(exe_path, os.X_OK), f"{exe_path} is not executable."

    with open(exe_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{exe_path} is not a compiled ELF executable."


def run_monitor(executable, args, env):
    return subprocess.run(
        [executable] + args,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )


def exercise_monitor(executable, workdir):
    config_path = "/home/user/iot_config.ini"
    spool_dir = os.path.join(workdir, "spool")
    os.makedirs(spool_dir, exist_ok=True)
    alert_path = os.path.join(spool_dir, "alert.eml")

    with open(config_path, "w") as f:
        f.write("AdminEmail=test-admin@example.invalid\n")
        f.write(f"SpoolDir={spool_dir}\n")

    env = os.environ.copy()
    env["EDGE_NODE_ID"] = "TEST-NODE-417"

    no_arg = run_monitor(executable, [], env)
    assert no_arg.returncode != 0, "monitor must reject invocation without a PID-file argument."

    extra_arg = run_monitor(executable, ["/tmp/a.pid", "/tmp/b.pid"], env)
    assert extra_arg.returncode != 0, "monitor must reject invocation with more than one argument."

    pid_file = os.path.join(workdir, "sensor.pid")
    sensor = subprocess.Popen(["sleep", "30"])
    try:
        with open(pid_file, "w") as f:
            f.write(str(sensor.pid) + "\n")

        if os.path.exists(alert_path):
            os.unlink(alert_path)
        alive = run_monitor(executable, [pid_file], env)
        assert alive.returncode == 0, f"running-process check returned {alive.returncode}: {alive.stderr}"
        assert alive.stdout.strip() == "OK", f"expected OK, got {alive.stdout!r}"
        assert not os.path.exists(alert_path), "monitor generated an alert for a running process."
    finally:
        sensor.terminate()
        sensor.wait(timeout=10)

    dead = run_monitor(executable, [pid_file], env)
    assert dead.returncode == 1, f"dead-process check returned {dead.returncode}: {dead.stderr}"
    assert dead.stdout.strip() == "ALERT GENERATED", f"expected ALERT GENERATED, got {dead.stdout!r}"
    expected_custom = (
        "To: test-admin@example.invalid\n"
        "Subject: ALERT: Node TEST-NODE-417 offline\n\n"
        "The sensor process is down.\n"
    )
    assert os.path.isfile(alert_path), "monitor did not create alert.eml in the configured SpoolDir."
    with open(alert_path, "r") as f:
        assert f.read() == expected_custom, "monitor did not use the configured email and environment node ID."

    os.unlink(alert_path)
    missing_pid = os.path.join(workdir, "missing.pid")
    missing = run_monitor(executable, [missing_pid], env)
    assert missing.returncode == 1, f"missing-PID-file check returned {missing.returncode}: {missing.stderr}"
    assert missing.stdout.strip() == "ALERT GENERATED"
    assert os.path.isfile(alert_path), "missing PID file did not generate an alert."

    os.unlink(alert_path)
    default_env = env.copy()
    default_env.pop("EDGE_NODE_ID", None)
    default_node = run_monitor(executable, [missing_pid], default_env)
    assert default_node.returncode == 1
    assert default_node.stdout.strip() == "ALERT GENERATED"
    with open(alert_path, "r") as f:
        default_content = f.read()
    assert "Subject: ALERT: Node UNKNOWN offline\n" in default_content, "unset EDGE_NODE_ID did not default to UNKNOWN."


def test_monitor_behavior_and_source():
    """Compile the submitted source and exercise both it and the deployed executable."""
    config_path = "/home/user/iot_config.ini"
    with open(config_path, "rb") as f:
        original_config = f.read()

    workdir = tempfile.mkdtemp(prefix="monitor-verifier-")
    rebuilt = os.path.join(workdir, "monitor-from-source")
    try:
        compile_result = subprocess.run(
            ["g++", "-std=c++11", "/home/user/monitor.cpp", "-o", rebuilt],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, f"monitor.cpp does not compile:\n{compile_result.stderr}"

        exercise_monitor("/home/user/monitor", os.path.join(workdir, "deployed"))
        exercise_monitor(rebuilt, os.path.join(workdir, "rebuilt"))
    finally:
        with open(config_path, "wb") as f:
            f.write(original_config)
        shutil.rmtree(workdir, ignore_errors=True)

    # Leave the required final alert behind using the submitted executable.
    os.makedirs("/home/user/mail_spool/outbox", exist_ok=True)
    final_alert = "/home/user/mail_spool/outbox/alert.eml"
    if os.path.exists(final_alert):
        os.unlink(final_alert)
    env = os.environ.copy()
    env["EDGE_NODE_ID"] = "IOT-992"
    result = run_monitor("/home/user/monitor", ["/tmp/verifier-definitely-missing-sensor.pid"], env)
    assert result.returncode == 1
    assert result.stdout.strip() == "ALERT GENERATED"


def test_alert_eml_content():
    """Verify the contents of the generated alert.eml."""
    alert_path = "/home/user/mail_spool/outbox/alert.eml"
    assert os.path.isfile(alert_path), f"{alert_path} does not exist. Did the monitor program run and generate it?"

    expected_content = (
        "To: ops@edge.local\n"
        "Subject: ALERT: Node IOT-992 offline\n\n"
        "The sensor process is down.\n"
    )

    with open(alert_path, "r") as f:
        actual_content = f.read()

    assert actual_content.strip() == expected_content.strip(), (
        f"Content of {alert_path} does not match expected.\n"
        f"Expected:\n{expected_content}\n"
        f"Actual:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
