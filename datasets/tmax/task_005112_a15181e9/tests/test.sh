#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import stat
import subprocess

SERVICE = "/home/user/.config/systemd/user/data-migrator.service"
TIMER = "/home/user/.config/systemd/user/data-migrator.timer"
WORKER = "/home/user/migration/worker.py"
OUTPUT = "/home/user/migration/output"
DATA = OUTPUT + "/data.txt"
HEALTH = "/home/user/migration/health_check.sh"
METRICS = "/home/user/migration/metrics.log"
USER_CONFIG = "/home/user/.config/systemd/user"


def read_unit(path):
    sections = {}
    section = None
    pending = ""
    with open(path, "r") as f:
        for raw in f:
            line = raw.rstrip("\n")
            if pending:
                line = pending + line.lstrip()
                pending = ""
            if line.endswith("\\") and not line.endswith("\\\\"):
                pending = line[:-1] + " "
                continue
            stripped = line.strip()
            if not stripped or stripped.startswith(("#", ";")):
                continue
            if stripped.startswith("[") and stripped.endswith("]"):
                section = stripped[1:-1]
                sections.setdefault(section, {})
                continue
            assert section is not None and "=" in line, f"Invalid unit syntax in {path}: {line!r}"
            key, value = line.split("=", 1)
            key = key.strip()
            sections[section].setdefault(key, []).append(value.strip())
    assert not pending, f"Unterminated continuation in {path}"
    return sections


def snapshot_file(path):
    if not os.path.exists(path):
        return None
    st = os.stat(path)
    with open(path, "rb") as f:
        data = f.read()
    return data, stat.S_IMODE(st.st_mode), st.st_uid, st.st_gid


def restore_file(path, snapshot):
    if snapshot is None:
        if os.path.lexists(path):
            os.unlink(path)
        return
    data, mode, uid, gid = snapshot
    with open(path, "wb") as f:
        f.write(data)
    os.chmod(path, mode)
    os.chown(path, uid, gid)


def run_as_user(argv, timeout=10, extra_env=None):
    env_args = [
        "HOME=/home/user",
        "USER=user",
        "LOGNAME=user",
        "PATH=/usr/local/bin:/usr/bin:/bin",
    ]
    if extra_env:
        env_args.extend(f"{k}={v}" for k, v in extra_env.items())
    return subprocess.run(
        ["runuser", "-u", "user", "--", "env", "-i", *env_args, *argv],
        capture_output=True, text=True, timeout=timeout
    )


def assert_enabled(unit_name, unit_path):
    links = []
    for root, dirs, files in os.walk(USER_CONFIG):
        if not (root.endswith(".wants") or root.endswith(".requires")):
            continue
        candidate = os.path.join(root, unit_name)
        if os.path.islink(candidate):
            links.append(candidate)
    assert links, f"{unit_name} is not enabled in the user systemd configuration"
    assert any(os.path.realpath(link) == os.path.realpath(unit_path) for link in links), \
        f"Enabled link for {unit_name} does not point to its unit file"


def test_output_directory_permissions():
    path = OUTPUT
    assert os.path.isdir(path), f"Directory {path} does not exist."
    st = os.stat(path)
    mode = oct(st.st_mode)[-3:]
    assert mode == "750", f"Directory {path} has permissions {mode}, expected 750."


def test_systemd_service_unit():
    path = SERVICE
    assert os.path.isfile(path), f"Service file {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "ExecStart=/home/user/migration/worker.py" in content, "ExecStart is missing or incorrect in service file."
    assert "WORKER_DATA_DIR=/home/user/migration/output" in content, "WORKER_DATA_DIR environment variable is missing or incorrect."
    assert "NODE_ENV=production" in content, "NODE_ENV environment variable is missing or incorrect."

    unit = read_unit(path)
    assert unit.get("Unit", {}).get("Description") == ["Data Migrator Worker"], \
        'Service description must be exactly "Data Migrator Worker".'
    service = unit.get("Service", {})
    assert "ExecStart" in service and len(service["ExecStart"]) == 1, "Service must define one ExecStart."
    command = shlex.split(service["ExecStart"][0])
    assert command and command[0] == WORKER, "ExecStart must execute the supplied worker.py."

    environment = {}
    for value in service.get("Environment", []):
        for assignment in shlex.split(value):
            assert "=" in assignment, f"Invalid Environment assignment: {assignment}"
            key, val = assignment.split("=", 1)
            environment[key] = val
    assert environment.get("WORKER_DATA_DIR") == OUTPUT
    assert environment.get("NODE_ENV") == "production"
    assert_enabled("data-migrator.service", SERVICE)


def test_systemd_timer_unit():
    path = TIMER
    assert os.path.isfile(path), f"Timer file {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert "OnCalendar=" in content, "OnCalendar configuration is missing in timer file."
    assert re.search(r"OnCalendar=.*(\*:0/5|\*:0,5|/\s*5)", content), \
        "Timer does not appear to be configured for every 5 minutes."

    unit = read_unit(path)
    timer = unit.get("Timer", {})
    assert len(timer.get("OnCalendar", [])) == 1, "Timer must have one OnCalendar schedule."
    expression = timer["OnCalendar"][0]
    check = subprocess.run(
        ["systemd-analyze", "calendar", expression], capture_output=True, text=True, timeout=10
    )
    assert check.returncode == 0, f"Invalid OnCalendar expression: {check.stderr or check.stdout}"
    normalized_match = re.search(r"Normalized form:\s+\*-\*-\*\s+\*:(\S+):00", check.stdout)
    assert normalized_match, f"Could not validate timer cadence from: {check.stdout}"
    minute_field = normalized_match.group(1)
    every_five_list = ",".join(f"{n:02d}" for n in range(0, 60, 5))
    assert minute_field in ("00/5", "0/5", every_five_list), \
        f"OnCalendar is not an every-five-minute schedule: {expression}"
    assert timer.get("Unit", ["data-migrator.service"])[-1] == "data-migrator.service", \
        "Timer does not trigger data-migrator.service."
    assert_enabled("data-migrator.timer", TIMER)

    verify = subprocess.run(
        ["systemd-analyze", "verify", SERVICE, TIMER], capture_output=True, text=True, timeout=15
    )
    assert verify.returncode == 0, f"systemd rejected the units:\n{verify.stdout}\n{verify.stderr}"


def test_service_command_really_runs_with_declared_environment():
    old_data = snapshot_file(DATA)
    try:
        if os.path.lexists(DATA):
            os.unlink(DATA)
        result = run_as_user(
            [WORKER],
            extra_env={"WORKER_DATA_DIR": OUTPUT, "NODE_ENV": "production"},
        )
        assert result.returncode == 0, f"Worker cannot run as the user: {result.stderr}"
        assert os.path.isfile(DATA), "Worker did not create data.txt in WORKER_DATA_DIR."
        with open(DATA, "r") as f:
            assert f.read().startswith("Processed at "), "Worker output is invalid."
    finally:
        restore_file(DATA, old_data)


def test_health_check_script():
    path = HEALTH
    assert os.path.isfile(path), f"Health check script {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {path} is not executable."
    with open(path, "r") as f:
        content = f.read()

    # Preserve the original assertions.
    assert DATA in content, "Script does not check for the correct data file."
    assert "STATUS: HEALTHY" in content, "Script does not contain the HEALTHY status string."
    assert "STATUS: DEGRADED" in content, "Script does not contain the DEGRADED status string."
    assert METRICS in content, "Script does not write to the correct metrics log file."

    old_data = snapshot_file(DATA)
    old_metrics = snapshot_file(METRICS)
    try:
        if os.path.lexists(DATA):
            os.unlink(DATA)
        with open(METRICS, "wb") as f:
            f.write(b"PREFIX\n")
        os.chown(METRICS, 1000, 1000)
        os.chmod(METRICS, 0o600)

        degraded = run_as_user([HEALTH], extra_env={"WORKER_DATA_DIR": OUTPUT})
        assert degraded.returncode == 0, f"Health check failed for missing data: {degraded.stderr}"
        with open(METRICS, "rb") as f:
            assert f.read() == b"PREFIX\nSTATUS: DEGRADED\n", \
                "Missing-data branch did not append exactly STATUS: DEGRADED."

        with open(DATA, "wb") as f:
            f.write(b"present\n")
        os.chmod(DATA, 0o644)
        healthy = run_as_user([HEALTH], extra_env={"WORKER_DATA_DIR": OUTPUT})
        assert healthy.returncode == 0, f"Health check failed for existing data: {healthy.stderr}"
        with open(METRICS, "rb") as f:
            assert f.read() == b"PREFIX\nSTATUS: DEGRADED\nSTATUS: HEALTHY\n", \
                "Existing-data branch did not append exactly STATUS: HEALTHY."
    finally:
        restore_file(DATA, old_data)
        restore_file(METRICS, old_metrics)


def test_crontab_configuration():
    result = subprocess.run(["crontab", "-u", "user", "-l"], capture_output=True, text=True)
    assert result.returncode == 0, "Failed to read user's crontab or no crontab exists."
    content = result.stdout

    # Preserve the original content assertions, applied to the instructed user's crontab.
    assert "health_check.sh" in content, "Crontab does not reference health_check.sh."
    assert "WORKER_DATA_DIR=/home/user/migration/output" in content, \
        "Crontab does not set WORKER_DATA_DIR correctly."

    active = [line.strip() for line in content.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    global_env_seen = False
    found_cron = False
    for line in active:
        if re.fullmatch(r"WORKER_DATA_DIR\s*=\s*/home/user/migration/output", line):
            global_env_seen = True
            continue
        parts = line.split(None, 5)
        if len(parts) != 6 or parts[:5] != ["*", "*", "*", "*", "*"]:
            continue
        command = parts[5]
        try:
            tokens = shlex.split(command)
        except ValueError:
            continue
        if HEALTH not in tokens:
            continue
        script_index = tokens.index(HEALTH)
        prefix = tokens[:script_index]
        inline_env = "WORKER_DATA_DIR=/home/user/migration/output" in prefix
        allowed_prefix = []
        for token in prefix:
            if token == "env" or token in ("bash", "/bin/bash", "sh", "/bin/sh") or re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", token):
                allowed_prefix.append(token)
            else:
                allowed_prefix = None
                break
        if allowed_prefix is not None and (global_env_seen or inline_env):
            found_cron = True
            break

    assert found_cron, \
        "User crontab must run the exact health_check.sh every minute with WORKER_DATA_DIR set before execution."
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
