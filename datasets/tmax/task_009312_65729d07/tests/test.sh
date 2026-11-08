#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import uuid

HOME_DIR = "/home/user"
INBOX_DIR = os.path.join(HOME_DIR, "provision_inbox")
ARCHIVE_DIR = os.path.join(HOME_DIR, "provision_archive")
WATCHER_SCRIPT = os.path.join(HOME_DIR, "watcher.sh")
LOG_FILE = os.path.join(HOME_DIR, "provision.log")
SERVICE_FILE = os.path.join(HOME_DIR, ".config/systemd/user/provision-watcher.service")
TIMER_FILE = os.path.join(HOME_DIR, ".config/systemd/user/provision-watcher.timer")
HEALTH_SCRIPT = os.path.join(HOME_DIR, "health.sh")


def read_unit_directives(path):
    directives = {}
    section = None
    with open(path, "r") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith(("#", ";")):
                continue
            if line.startswith("[") and line.endswith("]"):
                section = line[1:-1]
                continue
            if section is not None and "=" in line:
                key, value = line.split("=", 1)
                directives.setdefault((section, key.strip()), []).append(value.strip())
    return directives


def test_directories_exist():
    assert os.path.isdir(INBOX_DIR), f"Directory {INBOX_DIR} does not exist."
    assert os.path.isdir(ARCHIVE_DIR), f"Directory {ARCHIVE_DIR} does not exist."


def test_watcher_script_exists_and_executable():
    assert os.path.isfile(WATCHER_SCRIPT), f"Script {WATCHER_SCRIPT} does not exist."
    st = os.stat(WATCHER_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {WATCHER_SCRIPT} is not executable."


def test_watcher_script_behavior():
    test1 = os.path.join(INBOX_DIR, "test1.txt")
    test2 = os.path.join(INBOX_DIR, "test2.txt")
    ignore = os.path.join(INBOX_DIR, "ignore.json")

    with open(test1, "w") as f:
        f.write("1")
    with open(test2, "w") as f:
        f.write("2")
    with open(ignore, "w") as f:
        f.write("3")

    result = subprocess.run([WATCHER_SCRIPT], capture_output=True, text=True)
    assert result.returncode == 0, f"{WATCHER_SCRIPT} failed to execute."

    assert os.path.isfile(os.path.join(ARCHIVE_DIR, "test1.txt")), "test1.txt was not moved to the archive."
    assert os.path.isfile(os.path.join(ARCHIVE_DIR, "test2.txt")), "test2.txt was not moved to the archive."
    assert os.path.isfile(ignore), "ignore.json should not have been moved."
    assert not os.path.isfile(test1), "test1.txt was not removed from inbox."
    assert not os.path.isfile(test2), "test2.txt was not removed from inbox."

    assert os.path.isfile(LOG_FILE), f"Log file {LOG_FILE} was not created."
    with open(LOG_FILE, "r") as f:
        log_content = f.read()

    assert "PROVISIONED: test1.txt" in log_content, "Log file missing entry for test1.txt."
    assert "PROVISIONED: test2.txt" in log_content, "Log file missing entry for test2.txt."


def test_watcher_handles_unpredictable_txt_filenames():
    token = uuid.uuid4().hex
    txt_names = [
        f"application-{token}.txt",
        f"database_{token}.txt",
        f"worker.{token}.txt",
    ]
    ignored_name = f"metadata-{token}.json"

    for index, name in enumerate(txt_names):
        with open(os.path.join(INBOX_DIR, name), "w") as f:
            f.write(f"payload-{index}")
    ignored_path = os.path.join(INBOX_DIR, ignored_name)
    with open(ignored_path, "w") as f:
        f.write("not text")

    result = subprocess.run([WATCHER_SCRIPT], capture_output=True, text=True)
    assert result.returncode == 0, f"{WATCHER_SCRIPT} failed on dynamically named files: {result.stderr}"

    for name in txt_names:
        assert not os.path.exists(os.path.join(INBOX_DIR, name)), f"{name} was not removed from the inbox."
        assert os.path.isfile(os.path.join(ARCHIVE_DIR, name)), f"{name} was not moved to the archive."
    assert os.path.isfile(ignored_path), f"Non-txt file {ignored_name} should not have been moved."

    with open(LOG_FILE, "r") as f:
        log_lines = f.read().splitlines()
    for name in txt_names:
        assert f"PROVISIONED: {name}" in log_lines, f"Log file missing exact entry for {name}."


def test_systemd_service():
    assert os.path.isfile(SERVICE_FILE), f"Systemd service file {SERVICE_FILE} does not exist."
    with open(SERVICE_FILE, "r") as f:
        content = f.read()
    assert "ExecStart=/home/user/watcher.sh" in content, "Service file missing correct ExecStart."
    assert "Description=Provision Watcher" in content, "Service file missing correct Description."

    directives = read_unit_directives(SERVICE_FILE)
    assert "Provision Watcher" in directives.get(("Unit", "Description"), []), "Description must be set in the [Unit] section."
    assert "/home/user/watcher.sh" in directives.get(("Service", "ExecStart"), []), "ExecStart must be set in the [Service] section."


def test_systemd_timer():
    assert os.path.isfile(TIMER_FILE), f"Systemd timer file {TIMER_FILE} does not exist."
    with open(TIMER_FILE, "r") as f:
        content = f.read()
    assert "OnCalendar=*:0/2" in content, "Timer file missing correct OnCalendar value."

    directives = read_unit_directives(TIMER_FILE)
    assert "*:0/2" in directives.get(("Timer", "OnCalendar"), []), "OnCalendar must be set in the [Timer] section."
    timer_targets = directives.get(("Timer", "Unit"), [])
    assert not timer_targets or timer_targets[-1] == "provision-watcher.service", "Timer must trigger provision-watcher.service."


def test_systemd_units_are_valid():
    result = subprocess.run(
        ["systemd-analyze", "verify", SERVICE_FILE, TIMER_FILE],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Invalid systemd unit file(s):\n{result.stdout}{result.stderr}"


def test_health_script_exists_and_executable():
    assert os.path.isfile(HEALTH_SCRIPT), f"Script {HEALTH_SCRIPT} does not exist."
    st = os.stat(HEALTH_SCRIPT)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {HEALTH_SCRIPT} is not executable."


def test_health_script_behavior():
    if not os.path.exists(LOG_FILE):
        with open(LOG_FILE, "w") as f:
            f.write("test")

    result = subprocess.run([HEALTH_SCRIPT], capture_output=True, text=True)
    assert result.returncode == 0, f"{HEALTH_SCRIPT} failed to execute."
    assert result.stdout.strip() == "STATUS: OK", "Health script did not output 'STATUS: OK' when log exists."

    os.remove(LOG_FILE)
    result = subprocess.run([HEALTH_SCRIPT], capture_output=True, text=True)
    assert result.returncode == 0, f"{HEALTH_SCRIPT} failed to execute."
    assert result.stdout.strip() == "STATUS: PENDING", "Health script did not output 'STATUS: PENDING' when log is missing."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
