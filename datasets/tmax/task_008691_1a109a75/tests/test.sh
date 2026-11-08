#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import shutil
import subprocess
import tempfile
import uuid

HOME = "/home/user"
WATCHDOG = f"{HOME}/watchdog"
SOURCE = f"{HOME}/watchdog.c"
MAILER = f"{HOME}/mailer.sh"
DEPLOY = f"{HOME}/deploy.sh"
LOG = f"{HOME}/watchdog.log"
OUTBOX = f"{HOME}/outbox"
EML = f"{OUTBOX}/alerts.eml"


def run(cmd, timeout=15, **kwargs):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=timeout, **kwargs)


def test_00_deployment_pipeline_executes():
    assert os.path.isfile(SOURCE), f"Missing file: {SOURCE}"
    assert os.path.isfile(MAILER), f"Missing file: {MAILER}"
    assert os.path.isfile(DEPLOY), f"Missing file: {DEPLOY}"

    token = uuid.uuid4().hex
    count_path = f"/tmp/sensor-count-{token}"
    marker_path = f"/tmp/mailer-called-{token}"
    sensor_source = f"/tmp/sensor-{token}.c"
    saved_mailer = f"/tmp/mailer-{token}.sh"

    with open(sensor_source, "w") as f:
        f.write(r'''#include <stdio.h>
#include <stdlib.h>
int main(void) {
    const char *p = getenv("SENSOR_COUNT_FILE");
    if (p) {
        FILE *f = fopen(p, "a");
        if (f) { fputs("run\n", f); fclose(f); }
    }
    return 23;
}
''')
    subprocess.run(["gcc", sensor_source, "-o", f"{HOME}/sensor_app"], check=True)
    os.chmod(f"{HOME}/sensor_app", 0o755)

    shutil.copy2(MAILER, saved_mailer)
    with open(MAILER, "w") as f:
        f.write("#!/bin/bash\n")
        f.write(f"echo called > {marker_path!r}\n")
        f.write(f"exec /bin/bash {saved_mailer!r} \"$@\"\n")
    os.chmod(MAILER, 0o755)

    try:
        if os.path.lexists(WATCHDOG):
            os.remove(WATCHDOG)
        for path in (LOG, EML, count_path, marker_path):
            if os.path.lexists(path):
                os.remove(path)
        os.makedirs(OUTBOX, exist_ok=True)
        os.chmod(OUTBOX, 0o777)

        env = os.environ.copy()
        env["SENSOR_COUNT_FILE"] = count_path
        result = run(["/bin/bash", DEPLOY], cwd=HOME, env=env, timeout=20)
        assert result.returncode == 0, (
            f"deploy.sh failed with {result.returncode}: "
            f"{result.stderr.decode(errors='replace')}"
        )
        assert os.path.isfile(WATCHDOG), "deploy.sh did not produce /home/user/watchdog"
        assert os.path.isfile(marker_path), "deploy.sh did not run /home/user/mailer.sh"
        assert os.path.isfile(count_path), "the deployed watchdog did not execute sensor_app"
        with open(count_path) as f:
            assert len(f.readlines()) == 3, "sensor_app was not executed exactly three times"
    finally:
        shutil.copy2(saved_mailer, MAILER)
        os.chmod(MAILER, 0o755)


def test_watchdog_exists_and_executable():
    watchdog_path = "/home/user/watchdog"
    assert os.path.isfile(watchdog_path), f"Missing file: {watchdog_path}"

    st = os.stat(watchdog_path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File is not executable: {watchdog_path}"


def test_outbox_permissions():
    outbox_path = "/home/user/outbox"
    assert os.path.isdir(outbox_path), f"Missing directory: {outbox_path}"

    st = os.stat(outbox_path)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o700, f"Incorrect permissions on {outbox_path}, expected 0o700 but got {oct(perms)}"


def test_watchdog_log_contents():
    log_path = "/home/user/watchdog.log"
    assert os.path.isfile(log_path), f"Missing file: {log_path}"

    with open(log_path, 'r') as f:
        lines = f.readlines()

    alert_lines = [line for line in lines if line.strip() == "[ALERT] Child crashed"]
    assert len(alert_lines) == 3, f"Expected exactly 3 alerts in {log_path}, found {len(alert_lines)}"


def test_alerts_eml_contents():
    eml_path = "/home/user/outbox/alerts.eml"
    assert os.path.isfile(eml_path), f"Missing file: {eml_path}"

    with open(eml_path, 'r') as f:
        lines = f.readlines()

    subject_lines = [line for line in lines if line.strip() == "Subject: Edge Device Alert - Process Restarted"]
    assert len(subject_lines) == 3, f"Expected exactly 3 subjects in {eml_path}, found {len(subject_lines)}"


def exercise_watchdog(binary):
    with tempfile.TemporaryDirectory() as td:
        clean_count = os.path.join(td, "clean-count")
        crash_count = os.path.join(td, "crash-count")
        signal_count = os.path.join(td, "signal-count")

        clean = os.path.join(td, "clean")
        crash = os.path.join(td, "crash")
        signaled = os.path.join(td, "signaled")
        scripts = {
            clean: f"#!/bin/sh\necho run >> {clean_count}\nexit 0\n",
            crash: f"#!/bin/sh\necho run >> {crash_count}\nexit 9\n",
            signaled: f"#!/bin/sh\necho run >> {signal_count}\nkill -TERM $$\n",
        }
        for path, body in scripts.items():
            with open(path, "w") as f:
                f.write(body)
            os.chmod(path, 0o755)

        clean_log = os.path.join(td, "clean.log")
        with open(clean_log, "w") as f:
            f.write("existing\n")
        result = run([binary, clean, clean_log])
        assert result.returncode == 0, "watchdog did not exit 0 after a clean child exit"
        with open(clean_count) as f:
            assert len(f.readlines()) == 1, "clean child was not executed exactly once"
        with open(clean_log) as f:
            assert not any(line.strip() == "[ALERT] Child crashed" for line in f)

        for child, counter, name in ((crash, crash_count, "non-zero exit"),
                                     (signaled, signal_count, "signal termination")):
            log = os.path.join(td, name.replace(" ", "-") + ".log")
            with open(log, "w") as f:
                f.write("existing\n")
            result = run([binary, child, log])
            assert result.returncode == 1, f"watchdog did not exit 1 after three crashes ({name})"
            with open(counter) as f:
                assert len(f.readlines()) == 3, f"child was not restarted exactly twice ({name})"
            with open(log) as f:
                lines = f.readlines()
            assert lines[0] == "existing\n", "watchdog did not append to the log"
            alerts = [line for line in lines if line == "[ALERT] Child crashed\n"]
            assert len(alerts) == 3, f"watchdog did not append three exact alerts ({name})"


def test_watchdog_runtime_behavior_and_c_source():
    exercise_watchdog(WATCHDOG)

    with tempfile.TemporaryDirectory() as td:
        built = os.path.join(td, "watchdog-from-source")
        result = run(["gcc", SOURCE, "-o", built])
        assert result.returncode == 0, (
            "watchdog.c does not compile: " + result.stderr.decode(errors="replace")
        )
        exercise_watchdog(built)

    for args in ([], ["/bin/true"], ["/bin/true", "/tmp/x", "extra"]):
        result = run([WATCHDOG] + args, timeout=3)
        assert result.returncode != 0, "watchdog accepted a command line without exactly two arguments"


def test_mailer_processes_variable_alert_input_and_creates_outbox():
    token = uuid.uuid4().hex
    saved_log = f"/tmp/watchdog-log-{token}"
    saved_outbox = f"/tmp/outbox-{token}"
    had_log = os.path.exists(LOG)
    had_outbox = os.path.exists(OUTBOX)

    if had_log:
        shutil.copy2(LOG, saved_log)
    if had_outbox:
        shutil.move(OUTBOX, saved_outbox)

    try:
        with open(LOG, "w") as f:
            f.write("ordinary line\n")
            f.write("prefix [ALERT] first\n")
            f.write("[ALERT] second\n")
        result = run(["/bin/bash", MAILER])
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        assert os.path.isdir(OUTBOX), "mailer.sh did not create /home/user/outbox"
        assert os.path.isfile(EML), "mailer.sh did not create alerts.eml"
        with open(EML) as f:
            lines = f.readlines()
        subject = "Subject: Edge Device Alert - Process Restarted"
        assert sum(line.strip() == subject for line in lines) == 2

        with open(LOG, "w") as f:
            f.write("another [ALERT] line\n")
        result = run(["/bin/bash", MAILER])
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        with open(EML) as f:
            lines = f.readlines()
        assert sum(line.strip() == subject for line in lines) == 3, "mailer.sh did not append"
    finally:
        if os.path.exists(OUTBOX):
            shutil.rmtree(OUTBOX)
        if had_outbox:
            shutil.move(saved_outbox, OUTBOX)
        if had_log:
            shutil.copy2(saved_log, LOG)
        elif os.path.exists(LOG):
            os.remove(LOG)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
