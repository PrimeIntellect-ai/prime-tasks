#!/bin/bash
set -e
mkdir -p /logs/verifier

# Clear any backend left behind by the agent's earlier run.
pkill -f '/home/user/restore/mock_db.sh' 2>/dev/null || true
pkill -x nc 2>/dev/null || true
sleep 1

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import signal
import socket
import subprocess
import tarfile
import threading

RESTORE = "/home/user/restore"
MAILER = f"{RESTORE}/bin/mailer"
START_ALL = f"{RESTORE}/start_all.sh"
SUCCESS_LOG = "/home/user/success.log"
MARKER = "/tmp/verifier_mailer_invoked"


def stop_backends():
    subprocess.run(["pkill", "-f", "/home/user/restore/mock_db.sh"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-x", "nc"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def test_restored_compiled_and_started_stack():
    assert os.path.isfile(f"{RESTORE}/src/mailer.c"), "The restored C source is missing."
    assert os.path.isfile(f"{RESTORE}/mock_db.sh"), "The restored backend script is missing."
    assert os.path.isfile(START_ALL), "The restored startup script is missing."
    assert os.access(START_ALL, os.X_OK), "The startup script is not executable."
    assert os.path.isfile(MAILER), "The compiled mailer is missing."
    assert os.access(MAILER, os.X_OK), "The compiled mailer is not executable."

    with open(MAILER, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The mailer is not a compiled ELF executable."

    with tarfile.open("/home/user/mda_backup.tar.gz", "r:gz") as archive:
        original = archive.extractfile("start_all.sh").read()
    with open(START_ALL, "rb") as f:
        modified = f.read()
    assert modified != original, "start_all.sh was not modified to fix the race condition."

    # Exercise the compiled mailer against a verifier-generated backend response.
    stop_backends()
    token = str(secrets.randbelow(900000) + 100000)
    ready = threading.Event()
    server_errors = []

    def backend():
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
                server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                server.bind(("127.0.0.1", 9050))
                server.listen(1)
                ready.set()
                conn, _ = server.accept()
                with conn:
                    conn.sendall(token.encode())
        except BaseException as exc:
            server_errors.append(exc)
            ready.set()

    thread = threading.Thread(target=backend, daemon=True)
    thread.start()
    assert ready.wait(3), "The verifier backend did not become ready."
    assert not server_errors, f"Could not start verifier backend: {server_errors}"

    if os.path.exists(SUCCESS_LOG):
        os.remove(SUCCESS_LOG)
    result = subprocess.run([MAILER], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, timeout=5)
    thread.join(3)
    assert result.returncode == 0, f"The compiled mailer failed: {result.stdout}"
    assert os.path.isfile(SUCCESS_LOG), "The compiled mailer did not create success.log."
    with open(SUCCESS_LOG, "r") as f:
        assert f.read().strip() == f"[SUCCESS] Loaded {token} users from backup"

    # Instrument the required mailer path, then execute the submitted startup
    # script with the real delayed backend. This verifies that the script waits
    # for the backend and actually invokes the compiled mailer.
    stop_backends()
    real_mailer = MAILER + ".verifier-real"
    if os.path.exists(MARKER):
        os.remove(MARKER)
    if os.path.exists(SUCCESS_LOG):
        os.remove(SUCCESS_LOG)
    os.rename(MAILER, real_mailer)
    try:
        with open(MAILER, "w") as f:
            f.write("#!/bin/bash\necho invoked > /tmp/verifier_mailer_invoked\n"
                    "exec /home/user/restore/bin/mailer.verifier-real \"$@\"\n")
        os.chmod(MAILER, 0o755)

        proc = subprocess.Popen([START_ALL], stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True,
                                start_new_session=True)
        try:
            output, _ = proc.communicate(timeout=15)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            output, _ = proc.communicate()
            raise AssertionError(f"start_all.sh timed out: {output}")

        assert proc.returncode == 0, f"start_all.sh failed: {output}"
        assert os.path.isfile(MARKER), "start_all.sh did not execute the required mailer path."
    finally:
        if os.path.exists(MAILER):
            os.remove(MAILER)
        if os.path.exists(real_mailer):
            os.rename(real_mailer, MAILER)
        stop_backends()

    # Preserve the original verifier's success-log assertions.
    assert os.path.exists(SUCCESS_LOG), (
        f"The log file {SUCCESS_LOG} does not exist. "
        "This indicates the mailer did not successfully run and connect to the backend."
    )
    assert os.path.isfile(SUCCESS_LOG), f"{SUCCESS_LOG} is not a regular file."
    with open(SUCCESS_LOG, "r") as f:
        content = f.read().strip()
    expected_content = "[SUCCESS] Loaded 854 users from backup"
    assert content == expected_content, (
        f"The contents of {SUCCESS_LOG} are incorrect.\n"
        f"Expected: '{expected_content}'\nFound: '{content}'"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
