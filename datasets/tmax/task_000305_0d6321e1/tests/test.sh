#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import time
import uuid
import signal
import socket
import subprocess
import pytest

SCRIPT_PATH = "/home/user/start_iot.sh"
FSTAB_PATH = "/home/user/system/fstab.iot"
MAIL_LOG = "/home/user/mail_received.log"


def test_fstab_fixed():
    assert os.path.isfile(FSTAB_PATH), f"fstab file {FSTAB_PATH} is missing."

    with open(FSTAB_PATH, "r") as f:
        content = f.read()

    pattern = r"^/home/user/iot_storage\s+/mnt/iot_data\s+bind\s+defaults,bind\s+0\s+0$"
    match = any(re.match(pattern, line.strip()) for line in content.splitlines())
    assert match, "fstab.iot does not contain the correct bind mount configuration for /home/user/iot_storage."


def test_mail_conf_fixed():
    mail_conf_path = "/home/user/config/mail.conf"
    assert os.path.isfile(mail_conf_path), f"mail.conf file {mail_conf_path} is missing."

    with open(mail_conf_path, "r") as f:
        content = f.read()

    assert re.search(r"^SMTP_HOST=127\.0\.0\.1$", content, re.MULTILINE), "SMTP_HOST is not set to 127.0.0.1 in mail.conf."
    assert re.search(r"^SMTP_PORT=2525$", content, re.MULTILINE), "SMTP_PORT is not set to 2525 in mail.conf."


def test_script_permissions_and_content():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    assert content.startswith("#!/bin/bash"), "Script does not start with #!/bin/bash."
    assert re.search(r"set\s+-[^\n]*e", content) or "set -e" in content, "Script does not contain 'set -e'."
    assert re.search(r"set\s+-[^\n]*u", content) or "set -u" in content, "Script does not contain 'set -u'."
    assert "wait" in content, "Script does not use 'wait' to block for background processes."

    syntax = subprocess.run(["bash", "-n", SCRIPT_PATH], capture_output=True, text=True)
    assert syntax.returncode == 0, f"Script has invalid Bash syntax: {syntax.stderr}"


def test_script_rejects_fstab_without_bind():
    with open(FSTAB_PATH, "r") as f:
        original = f.read()

    try:
        with open(FSTAB_PATH, "w") as f:
            f.write("/dev/sda1 / ext4 defaults 1 1\n")

        result = subprocess.run(
            [SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=3,
        )
        assert result.returncode == 1, "Script did not exit with code 1 when fstab.iot lacked 'bind'."
    finally:
        with open(FSTAB_PATH, "w") as f:
            f.write(original)


def proc_info(pid):
    try:
        with open(f"/proc/{pid}/stat", "r") as f:
            stat = f.read()
        rest = stat[stat.rfind(")") + 2:].split()
        state = rest[0]
        ppid = int(rest[1])
        starttime = rest[19]
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            argv = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
        return state, ppid, starttime, argv
    except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError, IndexError):
        return None


def direct_children(parent_pid):
    found = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        info = proc_info(int(name))
        if info is not None and info[1] == parent_pid:
            found.append((int(name), info))
    return found


def matching_children(parent_pid):
    smtp = []
    sensor = []
    for pid, info in direct_children(parent_pid):
        argv = info[3]
        if len(argv) == 2 and os.path.basename(argv[0]) == "python3" and argv[1] == "/home/user/bin/smtp_edge.py":
            smtp.append((pid, info[2]))
        if len(argv) == 2 and os.path.basename(argv[0]) == "bash" and argv[1] == "/home/user/bin/sensor_app.sh":
            sensor.append((pid, info[2]))
    return smtp, sensor


def process_identity_alive(identity):
    pid, starttime = identity
    info = proc_info(pid)
    return info is not None and info[2] == starttime and info[0] != "Z"


def listening_inodes_2525():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                lines = f.readlines()[1:]
        except FileNotFoundError:
            continue
        for line in lines:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            if state == "0A" and int(local.rsplit(":", 1)[1], 16) == 2525:
                inodes.add(fields[9])
    return inodes


def process_owns_listener(pid):
    inodes = listening_inodes_2525()
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                target = os.readlink(f"/proc/{pid}/fd/{fd}")
            except (FileNotFoundError, PermissionError):
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in inodes:
                return True
    except (FileNotFoundError, PermissionError):
        pass
    return False


def port_is_open():
    try:
        with socket.create_connection(("127.0.0.1", 2525), timeout=0.15):
            return True
    except OSError:
        return False


def force_cleanup(proc):
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            proc.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            pass


def run_lifecycle_test(sig, exercise_mail):
    assert not port_is_open(), "Port 2525 was already occupied before the lifecycle script started."

    if exercise_mail:
        try:
            os.remove(MAIL_LOG)
        except FileNotFoundError:
            pass

    proc = subprocess.Popen(
        [SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )

    try:
        smtp = []
        sensor = []
        deadline = time.time() + 4
        while time.time() < deadline:
            assert proc.poll() is None, "The lifecycle script exited before its services were running."
            smtp, sensor = matching_children(proc.pid)
            if len(smtp) == 1 and len(sensor) == 1 and process_owns_listener(smtp[0][0]):
                break
            time.sleep(0.05)

        assert len(smtp) == 1, "The script did not directly execute exactly one required smtp_edge.py process."
        assert len(sensor) == 1, "The script did not directly execute exactly one required sensor_app.sh process."
        assert process_owns_listener(smtp[0][0]), "The required smtp_edge.py process is not listening on port 2525."
        assert proc.poll() is None, "The lifecycle script did not remain running while its children were active."

        if exercise_mail:
            token = "VERIFY_" + uuid.uuid4().hex
            with socket.create_connection(("127.0.0.1", 2525), timeout=2) as client:
                client.sendall(token.encode())

            deadline = time.time() + 2
            received = ""
            while time.time() < deadline:
                try:
                    with open(MAIL_LOG, "r") as f:
                        received = f.read()
                except FileNotFoundError:
                    pass
                if token in received:
                    break
                time.sleep(0.05)
            assert token in received, "The required SMTP process did not receive the verifier's generated message."

        os.kill(proc.pid, sig)
        try:
            stdout, stderr = proc.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            pytest.fail("The script did not exit gracefully after receiving the test signal.")

        assert stdout == "CLEANUP_SUCCESS\n", f"Cleanup stdout was not exactly CLEANUP_SUCCESS: {stdout!r}"
        assert not process_identity_alive(smtp[0]), "smtp_edge.py was not killed by the script's cleanup trap."
        assert not process_identity_alive(sensor[0]), "sensor_app.sh was not killed by the script's cleanup trap."
    finally:
        force_cleanup(proc)


def test_script_execution_and_trap():
    run_lifecycle_test(signal.SIGINT, exercise_mail=False)
    run_lifecycle_test(signal.SIGTERM, exercise_mail=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
