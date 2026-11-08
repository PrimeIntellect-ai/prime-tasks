#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import random
import shutil
import stat
import subprocess
import tempfile

USER = pwd.getpwnam("user")


def run_as_user(argv, *, input_text=None, timeout=10):
    def demote():
        os.setgroups([])
        os.setgid(USER.pw_gid)
        os.setuid(USER.pw_uid)

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    env["USER"] = "user"
    env["LOGNAME"] = "user"
    return subprocess.run(
        argv,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        env=env,
        preexec_fn=demote,
        check=False,
    )


def test_sensor_conf():
    conf_path = "/home/user/edge_config/sensor.conf"
    assert os.path.isfile(conf_path), f"{conf_path} does not exist."

    with open(conf_path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "THRESHOLD=85.5" in content, "THRESHOLD=85.5 missing in sensor.conf"
    assert "SENSOR_ID=NODE_42" in content, "SENSOR_ID=NODE_42 missing in sensor.conf"
    assert "ALERT_EMAIL=admin@edge.local" in content, "ALERT_EMAIL=admin@edge.local missing in sensor.conf"

    assert content.splitlines() == [
        "THRESHOLD=85.5",
        "SENSOR_ID=NODE_42",
        "ALERT_EMAIL=admin@edge.local",
    ], "sensor.conf must contain exactly the three requested key-value lines"


def test_msmtprc():
    msmtprc_path = "/home/user/.msmtprc"
    assert os.path.isfile(msmtprc_path), f"{msmtprc_path} does not exist."

    st = os.stat(msmtprc_path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o600, f"{msmtprc_path} permissions are {oct(perms)}, expected 0o600."

    with open(msmtprc_path, "r") as f:
        content = f.read().lower()

    # Preserve the original assertions.
    assert "account default" in content or "account\tdefault" in content, "Account name 'default' missing in .msmtprc"
    assert "host localhost" in content or "host\tlocalhost" in content, "Host 'localhost' missing in .msmtprc"
    assert "port 2525" in content or "port\t2525" in content, "Port '2525' missing in .msmtprc"
    assert "from edge_node@local" in content or "from\tedge_node@local" in content, "From 'edge_node@local' missing in .msmtprc"
    assert "auth off" in content or "auth\toff" in content, "Auth 'off' missing in .msmtprc"

    directives = []
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        line = line.split("#", 1)[0].strip()
        parts = line.split(None, 1)
        assert len(parts) == 2, f"Invalid msmtp directive: {raw_line!r}"
        directives.append((parts[0], parts[1].strip()))

    assert directives == [
        ("account", "default"),
        ("host", "localhost"),
        ("port", "2525"),
        ("from", "edge_node@local"),
        ("auth", "off"),
    ], ".msmtprc must contain exactly the requested active settings"


def test_analyzer_executable():
    cpp_path = "/home/user/src/analyzer.cpp"
    bin_path = "/home/user/bin/analyzer"

    assert os.path.isfile(cpp_path), f"{cpp_path} does not exist."
    assert os.path.isfile(bin_path), f"{bin_path} does not exist."
    assert os.access(bin_path, os.X_OK), f"{bin_path} is not executable."
    with open(bin_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{bin_path} is not a compiled executable"


def test_process_telemetry_script():
    script_path = "/home/user/bin/process_telemetry.sh"
    assert os.path.isfile(script_path), f"{script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"{script_path} is not executable."


def test_alerts_generated():
    alerts_path = "/home/user/data/alerts_generated.txt"
    assert os.path.isfile(alerts_path), f"{alerts_path} does not exist. Did you run the script?"

    with open(alerts_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "ALERT: SENSOR_ID=NODE_42 VALUE=88.70",
        "ALERT: SENSOR_ID=NODE_42 VALUE=90.00",
        "ALERT: SENSOR_ID=NODE_42 VALUE=102.34",
    ]
    assert lines == expected_lines, f"Contents of {alerts_path} do not match the expected alerts."


def test_analyzer_behavior_and_source_build():
    rng = random.SystemRandom()
    below = [rng.randint(-5000, 8549) for _ in range(4)]
    above = [rng.randint(8551, 20000) for _ in range(5)]
    cents_values = below + [8550] + above
    rng.shuffle(cents_values)

    input_lines = [f"{c // 100}.{c % 100:02d}" for c in cents_values]
    input_text = "\n".join(input_lines) + "\n"
    expected = [
        f"ALERT: SENSOR_ID=NODE_42 VALUE={c // 100}.{c % 100:02d}"
        for c in cents_values if c > 8550
    ]

    installed = run_as_user(["/home/user/bin/analyzer"], input_text=input_text)
    assert installed.returncode == 0, installed.stderr
    assert installed.stdout.splitlines() == expected, "Installed analyzer failed dynamic threshold/formatting checks"

    build_dir = tempfile.mkdtemp(prefix="analyzer-build-")
    os.chmod(build_dir, 0o777)
    rebuilt = os.path.join(build_dir, "analyzer")
    try:
        compile_result = run_as_user([
            "g++", "/home/user/src/analyzer.cpp", "-o", rebuilt
        ], timeout=30)
        assert compile_result.returncode == 0, f"analyzer.cpp did not compile:\n{compile_result.stderr}"
        rebuilt_result = run_as_user([rebuilt], input_text=input_text)
        assert rebuilt_result.returncode == 0, rebuilt_result.stderr
        assert rebuilt_result.stdout.splitlines() == expected, "Program rebuilt from analyzer.cpp behaves incorrectly"
    finally:
        shutil.rmtree(build_dir, ignore_errors=True)


def test_process_telemetry_on_dynamic_log():
    raw_path = "/home/user/data/raw_sensors.log"
    alerts_path = "/home/user/data/alerts_generated.txt"
    script_path = "/home/user/bin/process_telemetry.sh"

    with open(raw_path, "rb") as f:
        original_raw = f.read()
    original_alerts = None
    if os.path.exists(alerts_path):
        with open(alerts_path, "rb") as f:
            original_alerts = f.read()

    rng = random.SystemRandom()
    valid_cents = [
        rng.randint(100, 8500),
        8550,
        rng.randint(8551, 12000),
        rng.randint(12001, 18000),
        rng.randint(8551, 20000),
    ]
    rng.shuffle(valid_cents)

    log_lines = ["[INFO] 2099-01-01 00:00:00 | val=999.99"]
    for i, cents in enumerate(valid_cents):
        number = f"{cents // 100}.{cents % 100:02d}"
        log_lines.append(f"[DATA] 2099-01-01 00:00:{i:02d} | val={number}")
        log_lines.append(f"[DEBUG] ignored-{i} | val=999.99")
    log_lines.append(" [DATA] leading-space-must-not-match | val=999.99")

    expected = [
        f"ALERT: SENSOR_ID=NODE_42 VALUE={c // 100}.{c % 100:02d}"
        for c in valid_cents if c > 8550
    ]

    try:
        with open(raw_path, "w") as f:
            f.write("\n".join(log_lines) + "\n")
        if os.path.exists(alerts_path):
            os.unlink(alerts_path)

        result = run_as_user([script_path], timeout=15)
        assert result.returncode == 0, f"process_telemetry.sh failed:\n{result.stderr}"
        assert os.path.isfile(alerts_path), "Pipeline did not create alerts_generated.txt"
        with open(alerts_path, "r") as f:
            actual = [line.strip() for line in f if line.strip()]
        assert actual == expected, "Pipeline did not extract and analyze the dynamic [DATA] records correctly"
    finally:
        with open(raw_path, "wb") as f:
            f.write(original_raw)
        if original_alerts is None:
            if os.path.exists(alerts_path):
                os.unlink(alerts_path)
        else:
            with open(alerts_path, "wb") as f:
                f.write(original_alerts)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
