#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import re
import stat
import subprocess
import time
from pathlib import Path

USER = "user"
HOME = Path("/home/user")
UNIT_DIR = HOME / ".config/systemd/user"
SERVICES = ["diagnostic-logger.service", "alert-sender.service"]


def user_systemctl(*args):
    uid = pwd.getpwnam(USER).pw_uid
    runtime = f"/run/user/{uid}"
    env_args = [
        f"HOME={HOME}",
        f"XDG_RUNTIME_DIR={runtime}",
        f"DBUS_SESSION_BUS_ADDRESS=unix:path={runtime}/bus",
    ]
    return subprocess.run(
        ["runuser", "-u", USER, "--", "env", *env_args, "systemctl", "--user", *args],
        capture_output=True,
        text=True,
    )


def unit_values(path, section, directive):
    current = None
    values = []
    for raw in Path(path).read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1].strip()
            continue
        if current != section or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key.strip() == directive:
            tokens = value.strip().split()
            if not tokens:
                values = []
            else:
                values.extend(tokens)
    return values


def user_processes():
    uid = pwd.getpwnam(USER).pw_uid
    result = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            if entry.stat().st_uid != uid:
                continue
            data = (entry / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace").strip()
            if data:
                result.append(data)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return result


def test_mailer_conf_updated():
    path = HOME / "mailer.conf"
    assert path.is_file(), f"File {path} is missing."
    assert path.read_text().strip() == "PORT=8025", \
        f"{path} must contain only PORT=8025"


def test_systemd_service_dependency():
    sender = UNIT_DIR / "alert-sender.service"
    assert sender.is_file(), f"Missing unit file {sender}"
    after = unit_values(sender, "Unit", "After")
    assert "diagnostic-logger.service" in after, \
        "alert-sender.service needs an active After=diagnostic-logger.service directive in [Unit]"


def test_systemd_services_enabled_and_active():
    for svc in SERVICES:
        unit = UNIT_DIR / svc
        assert unit.is_file(), f"Missing unit file {unit}"
        enabled = user_systemctl("is-enabled", svc)
        assert enabled.returncode == 0 and enabled.stdout.strip() in {"enabled", "enabled-runtime"}, \
            f"{svc} is not enabled: {enabled.stdout}{enabled.stderr}"

    pipe = HOME / "alert_pipe"
    assert pipe.exists() and stat.S_ISFIFO(pipe.stat().st_mode), \
        "/home/user/alert_pipe is missing or is not a named pipe"

    processes = user_processes()
    logger_running = any(
        re.search(r"(?:^|\s)tail\s+-f\s+/home/user/alert_pipe(?:\s|$)", cmd)
        for cmd in processes
    )
    sender_running = any(
        ("alert_pipe" in cmd and re.search(r"\bsleep\s+1000\b", cmd)) or
        re.search(r"(?:^|/)sleep\s+1000(?:\s|$)", cmd)
        for cmd in processes
    )

    for svc, fallback_running in [
        ("diagnostic-logger.service", logger_running),
        ("alert-sender.service", sender_running),
    ]:
        active = user_systemctl("is-active", svc)
        assert (active.returncode == 0 and active.stdout.strip() == "active") or fallback_running, \
            f"{svc} is not active and its configured process is not running: {active.stdout}{active.stderr}"


def test_check_endpoints_execution_time_output_and_real_checks():
    script = HOME / "bin/check_endpoints.sh"
    log = HOME / "endpoint_status.log"
    assert script.is_file(), f"Script {script} is missing."
    assert os.access(script, os.X_OK), f"Script {script} is not executable."
    assert script.read_bytes().startswith(b"#!") and b"bash" in script.read_bytes().splitlines()[0], \
        "check_endpoints.sh must be a Bash script"

    wrapper_dir = Path("/tmp/verifier-endpoint-bin")
    wrapper_dir.mkdir(exist_ok=True)
    trace = Path("/tmp/verifier-sleep-trace")
    trace.unlink(missing_ok=True)
    sleep_wrapper = wrapper_dir / "sleep"
    sleep_wrapper.write_text(
        "#!/bin/bash\n"
        "printf '%s\\t%s\\n' \"$$\" \"$*\" >> \"$VERIFIER_SLEEP_TRACE\"\n"
        "exec /bin/sleep \"$@\"\n"
    )
    sleep_wrapper.chmod(0o755)

    log.unlink(missing_ok=True)
    env = os.environ.copy()
    env["PATH"] = str(wrapper_dir) + os.pathsep + env.get("PATH", "")
    env["VERIFIER_SLEEP_TRACE"] = str(trace)

    start = time.monotonic()
    result = subprocess.run([str(script)], capture_output=True, text=True, env=env, timeout=2)
    duration = time.monotonic() - start

    assert result.returncode == 0, \
        f"Script failed with return code {result.returncode}. stderr: {result.stderr}"
    assert duration <= 0.5, f"Execution time {duration:.3f}s exceeded 0.5s"
    assert log.is_file(), f"Log file {log} was not created."

    expected = [f"Endpoint {i}: OK" for i in range(1, 51)]
    actual = log.read_text().splitlines()
    assert actual == expected, \
        "endpoint_status.log must contain the original 50 results in their original order and format"

    assert trace.is_file(), "The endpoint script did not perform the simulated connectivity checks"
    checks = [line.split("\t", 1) for line in trace.read_text().splitlines() if line]
    assert len(checks) == 50, f"Expected 50 connectivity checks, observed {len(checks)}"
    assert all(len(item) == 2 and item[1].strip() == "0.1" for item in checks), \
        f"Each original 0.1-second connectivity check must still run; observed: {checks}"
    assert len({item[0] for item in checks}) > 1, "Connectivity checks were not launched in parallel"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
