#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import socket
import stat
import subprocess

PIN_FILE = "/home/user/cracked_pin.txt"
SCRIPT_FILE = "/home/user/honeypot.sh"
TARGET_TOKEN = "7e82e88d1d86e100f7ef82283ccb3c07"


def test_cracked_pin_file():
    assert os.path.exists(PIN_FILE), f"File {PIN_FILE} does not exist."
    with open(PIN_FILE, "r") as f:
        content = f.read().strip()
    assert content == "4921", f"Expected PIN '4921' in {PIN_FILE}, but found '{content}'."


def test_honeypot_script_exists_and_executable():
    assert os.path.exists(SCRIPT_FILE), f"Script {SCRIPT_FILE} does not exist."
    assert os.access(SCRIPT_FILE, os.X_OK), f"Script {SCRIPT_FILE} is not executable."


def _tcp_interaction(pin_to_send):
    try:
        with socket.create_connection(("127.0.0.1", 9000), timeout=3) as s:
            s.settimeout(3)
            s.sendall(f"{pin_to_send}\n".encode("utf-8"))
            chunks = []
            while True:
                data = s.recv(1024)
                if not data:
                    break
                chunks.append(data)
            return b"".join(chunks).decode("utf-8").strip()
    except ConnectionRefusedError:
        raise AssertionError("Connection refused on 127.0.0.1:9000. Is socat running?")
    except socket.timeout:
        raise AssertionError("Connection timed out waiting for response from 127.0.0.1:9000.")
    except AssertionError:
        raise
    except Exception as e:
        raise AssertionError(f"An error occurred while connecting to 127.0.0.1:9000: {e}")


def _test_tcp_interaction(pin_to_send, expected_response):
    response = _tcp_interaction(pin_to_send)
    assert response == expected_response, (
        f"Expected '{expected_response}' for PIN {pin_to_send}, but got '{response}'."
    )


def test_socat_honeypot_correct_pin():
    _test_tcp_interaction("4921", "ACCESS_DENIED_HONEYPOT")


def test_socat_honeypot_incorrect_pin():
    _test_tcp_interaction("1111", "INVALID_PIN")


def _listening_socket_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    local_address = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local_address.rsplit(":", 1)[1], 16) == port:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def _listener_processes(port):
    inodes = _listening_socket_inodes(port)
    owners = []
    for proc_dir in glob.glob("/proc/[0-9]*"):
        pid = os.path.basename(proc_dir)
        owns_socket = False
        for fd in glob.glob(f"{proc_dir}/fd/*"):
            try:
                if os.readlink(fd) in {f"socket:[{inode}]" for inode in inodes}:
                    owns_socket = True
                    break
            except OSError:
                continue
        if owns_socket:
            try:
                exe = os.path.basename(os.readlink(f"{proc_dir}/exe"))
                with open(f"{proc_dir}/cmdline", "rb") as f:
                    cmdline = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
                owners.append((pid, exe, cmdline))
            except OSError:
                pass
    return owners


def test_port_is_owned_by_socat_and_executes_required_script():
    owners = _listener_processes(9000)
    socat_owners = [entry for entry in owners if entry[1] == "socat"]
    assert socat_owners, f"TCP port 9000 is not owned by a socat process; owners were {owners!r}."
    assert any(SCRIPT_FILE in cmdline for _, _, cmdline in socat_owners), (
        f"The socat listener command does not reference {SCRIPT_FILE}; processes were {socat_owners!r}."
    )

    # Temporarily substitute an unpredictable probe at the required path. A new
    # connection must execute this file, proving the listener is not an unrelated
    # or hardcoded service whose command line merely mentions the path.
    marker = "VERIFIER_PROBE_" + secrets.token_hex(24)
    backup = SCRIPT_FILE + ".verifier_backup_" + secrets.token_hex(8)
    original_mode = stat.S_IMODE(os.stat(SCRIPT_FILE).st_mode)
    os.replace(SCRIPT_FILE, backup)
    try:
        with open(SCRIPT_FILE, "w") as f:
            f.write("#!/bin/bash\n")
            f.write("read -r _\n")
            f.write(f"printf '%s\\n' '{marker}'\n")
        os.chmod(SCRIPT_FILE, 0o755)
        response = _tcp_interaction("0000")
        assert response == marker, (
            f"The listener did not execute {SCRIPT_FILE}; probe returned {response!r}."
        )
    finally:
        try:
            os.unlink(SCRIPT_FILE)
        except FileNotFoundError:
            pass
        os.replace(backup, SCRIPT_FILE)
        os.chmod(SCRIPT_FILE, original_mode)


def _expected_response(pin):
    generated = subprocess.run(
        ["/app/c2_auth", pin],
        check=True,
        text=True,
        capture_output=True,
        timeout=3,
    ).stdout.strip()
    return "ACCESS_DENIED_HONEYPOT" if generated == TARGET_TOKEN else "INVALID_PIN"


def _dynamic_pins():
    pins = {"0000", "9999", "4921"}
    while len(pins) < 43:
        pins.add(f"{secrets.randbelow(10000):04d}")
    return sorted(pins)


def test_honeypot_script_and_tcp_service_on_dynamic_inputs():
    for pin in _dynamic_pins():
        expected = _expected_response(pin)

        direct = subprocess.run(
            ["/bin/bash", SCRIPT_FILE],
            input=pin + "\n",
            text=True,
            capture_output=True,
            timeout=3,
        )
        assert direct.returncode == 0, f"{SCRIPT_FILE} exited with status {direct.returncode} for PIN {pin}."
        assert direct.stdout.strip() == expected, (
            f"Direct execution expected '{expected}' for PIN {pin}, but got {direct.stdout.strip()!r}."
        )

        _test_tcp_interaction(pin, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
