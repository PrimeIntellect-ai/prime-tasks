#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

WORKDIR=$(mktemp -d /tmp/iot-verifier.XXXXXX)
export VERIFIER_TRANSCRIPT="$WORKDIR/transcript.txt"
export VERIFIER_READY="$WORKDIR/ready"
SERVER_PID=""

cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

# Replace the original simulator with a verifier-controlled instance so a
# hardcoded confirmation file cannot masquerade as a successful TCP exchange.
for pid in $(ss -H -ltnp 'sport = :8888' 2>/dev/null | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p'); do
    kill "$pid" 2>/dev/null || true
done
sleep 0.2

cat > "$WORKDIR/server.py" <<'PY_EOF'
import os
import socket
import threading

transcript = os.environ["VERIFIER_TRANSCRIPT"]
ready = os.environ["VERIFIER_READY"]
log_path = "/home/user/device_sync_log.txt"
lock = threading.Lock()

def recv_line(conn):
    data = b""
    while len(data) < 4096:
        chunk = conn.recv(1024)
        if not chunk:
            break
        data += chunk
        if b"\n" in data or b"\r" in data:
            break
    return data.decode("utf-8", "replace").strip()

def handle(conn):
    try:
        conn.settimeout(5)
        conn.sendall(b"Device login:")
        password = recv_line(conn)
        if password != "edgeAdmin":
            conn.sendall(b"AUTH_FAILED\n")
            return
        conn.sendall(b"Command>")
        command = recv_line(conn)
        with lock:
            with open(transcript, "a", encoding="utf-8") as f:
                f.write(password + "|" + command + "\n")
        if command == "SYNC /home/user/deploy_stage":
            with open(log_path, "w", encoding="utf-8") as f:
                f.write("SYNC_SUCCESS: /home/user/deploy_stage\n")
            conn.sendall(b"OK\n")
        else:
            conn.sendall(b"ERROR\n")
    except Exception:
        pass
    finally:
        conn.close()

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 8888))
s.listen(10)
open(ready, "w").close()
while True:
    conn, _ = s.accept()
    threading.Thread(target=handle, args=(conn,), daemon=True).start()
PY_EOF

python3 "$WORKDIR/server.py" &
SERVER_PID=$!
for _ in $(seq 1 50); do
    [ -f "$VERIFIER_READY" ] && break
    kill -0 "$SERVER_PID" 2>/dev/null || break
    sleep 0.1
done

if [ ! -f "$VERIFIER_READY" ]; then
    exit 0
fi

cat <<'TEST_EOF' > "$WORKDIR/test_final_state.py"
import os
import shutil
import stat
import subprocess
import tempfile
import time
import uuid

import pytest

REPO = "/home/user/iot_repo.git"
DEPLOY = "/home/user/deploy_stage"
SCRIPT = "/home/user/trigger_sync.exp"
TRANSCRIPT = os.environ["VERIFIER_TRANSCRIPT"]
EXPECTED_EXCHANGE = "edgeAdmin|SYNC /home/user/deploy_stage"


def wait_for_file(path, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.isfile(path):
            return
        time.sleep(0.05)
    raise AssertionError(f"Timed out waiting for {path}")


def clear_runtime_evidence():
    for path in (TRANSCRIPT, "/home/user/device_sync_log.txt"):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def assert_valid_exchange():
    wait_for_file(TRANSCRIPT)
    wait_for_file("/home/user/device_sync_log.txt")
    with open(TRANSCRIPT, encoding="utf-8") as f:
        exchanges = [line.strip() for line in f if line.strip()]
    assert EXPECTED_EXCHANGE in exchanges, (
        "The Expect script did not send the required password and SYNC command "
        "to the TCP simulator."
    )


def test_00_pipeline_is_actually_triggered_by_push():
    assert os.path.isfile(SCRIPT), f"Expect script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Expect script {SCRIPT} is not executable."

    with open(SCRIPT, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(SCRIPT).st_mode)
    text = original.decode("utf-8")
    lines = text.splitlines(keepends=True)
    assert lines and lines[0].startswith("#!") and "expect" in lines[0].lower(), (
        f"{SCRIPT} must be an Expect script with an Expect shebang."
    )

    # Exercise the submitted Expect program directly against the controlled
    # simulator. The transcript, rather than a pre-created log, proves TCP use.
    clear_runtime_evidence()
    direct = subprocess.run(
        ["/usr/bin/expect", SCRIPT],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=15,
    )
    assert direct.returncode == 0, f"Expect script failed:\n{direct.stdout}"
    assert_valid_exchange()

    marker = os.path.join(tempfile.gettempdir(), "hook-called-" + uuid.uuid4().hex)
    tcl_marker = (
        f'set __verifier_marker [open "{marker}" w]\n'
        'puts $__verifier_marker "called"\n'
        'close $__verifier_marker\n'
    )
    instrumented = lines[0] + tcl_marker + "".join(lines[1:])

    clone_dir = tempfile.mkdtemp(prefix="iot-verifier-clone-")
    probe_name = "verifier_probe_" + uuid.uuid4().hex + ".txt"
    probe_value = "pushed-by-verifier-" + uuid.uuid4().hex
    try:
        # Instrument the actual submitted script at its required path. The
        # unpredictable marker proves that post-receive invoked that path.
        with open(SCRIPT, "w", encoding="utf-8") as f:
            f.write(instrumented)
        os.chmod(SCRIPT, original_mode)

        clone = subprocess.run(
            ["git", "clone", REPO, clone_dir],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=20,
        )
        assert clone.returncode == 0, f"Could not clone the bare repository:\n{clone.stdout}"

        branch = subprocess.check_output(
            ["git", "-C", clone_dir, "symbolic-ref", "--short", "HEAD"],
            text=True,
        ).strip()
        assert branch, "The cloned repository has no checked-out branch."

        firmware_in_commit = subprocess.check_output(
            ["git", "-C", clone_dir, "show", "HEAD:firmware.bin"], text=True
        )
        assert firmware_in_commit == "v1.2.0", (
            "The pushed repository commit must contain firmware.bin with exactly 'v1.2.0'."
        )

        with open(os.path.join(clone_dir, probe_name), "w", encoding="utf-8") as f:
            f.write(probe_value)
        subprocess.run(["git", "-C", clone_dir, "add", probe_name], check=True)
        subprocess.run(
            ["git", "-C", clone_dir, "-c", "user.name=Verifier", "-c",
             "user.email=verifier@example.invalid", "commit", "-m", "Verifier pipeline probe"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

        # Destroy prior evidence. A successful test now requires this push to
        # restore tracked deployment content, regenerate routing output, invoke
        # the submitted Expect path, and complete a real TCP exchange.
        os.makedirs(DEPLOY, exist_ok=True)
        with open(os.path.join(DEPLOY, "firmware.bin"), "w", encoding="utf-8") as f:
            f.write("VERIFIER_SENTINEL")
        for path in (os.path.join(DEPLOY, probe_name), os.path.join(DEPLOY, "route_info.txt")):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
        clear_runtime_evidence()

        pushed = subprocess.run(
            ["git", "-C", clone_dir, "push", "origin", f"HEAD:{branch}"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=30,
        )
        assert pushed.returncode == 0, f"Git push or post-receive hook failed:\n{pushed.stdout}"

        wait_for_file(marker)
        assert_valid_exchange()

        deployed_probe = os.path.join(DEPLOY, probe_name)
        wait_for_file(deployed_probe)
        with open(deployed_probe, encoding="utf-8") as f:
            assert f.read() == probe_value, (
                "The post-receive hook did not check out the newly pushed file."
            )

        with open(os.path.join(DEPLOY, "firmware.bin"), encoding="utf-8") as f:
            assert f.read() == "v1.2.0", (
                "The push did not replace the deployment sentinel with the committed firmware."
            )

        route_path = os.path.join(DEPLOY, "route_info.txt")
        wait_for_file(route_path)
        expected_route = subprocess.check_output(
            ["ip", "route", "get", "8.8.8.8"], text=True
        )
        with open(route_path, encoding="utf-8") as f:
            assert f.read().strip() == expected_route.strip(), (
                "The post-receive hook did not regenerate the exact route command output."
            )
    finally:
        with open(SCRIPT, "wb") as f:
            f.write(original)
        os.chmod(SCRIPT, original_mode)
        shutil.rmtree(clone_dir, ignore_errors=True)
        try:
            os.unlink(marker)
        except FileNotFoundError:
            pass


def test_bare_repo_exists():
    repo_path = "/home/user/iot_repo.git"
    assert os.path.isdir(repo_path), f"Bare repository directory {repo_path} does not exist."
    assert os.path.isfile(os.path.join(repo_path, "config")), f"{repo_path} does not appear to be a valid Git repository."
    result = subprocess.check_output(
        ["git", "--git-dir", repo_path, "rev-parse", "--is-bare-repository"], text=True
    ).strip()
    assert result == "true", f"{repo_path} is not a valid bare Git repository."


def test_active_repo_symlink():
    symlink_path = "/home/user/active_repo"
    target_path = "/home/user/iot_repo.git"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."
    assert os.readlink(symlink_path) == target_path, f"Symlink {symlink_path} does not point to {target_path}."


def test_deploy_stage_directory():
    deploy_dir = "/home/user/deploy_stage"
    assert os.path.isdir(deploy_dir), f"Deployment directory {deploy_dir} does not exist."


def test_firmware_deployed():
    firmware_path = "/home/user/deploy_stage/firmware.bin"
    assert os.path.isfile(firmware_path), f"Deployed file {firmware_path} does not exist. Did the post-receive hook checkout the files?"
    with open(firmware_path, "r") as f:
        content = f.read().strip()
    assert content == "v1.2.0", f"Expected firmware.bin to contain 'v1.2.0', but got '{content}'."


def test_route_info_logged():
    route_file = "/home/user/deploy_stage/route_info.txt"
    assert os.path.isfile(route_file), f"Route info file {route_file} does not exist. Did the post-receive hook create it?"
    try:
        expected_output = subprocess.check_output(["ip", "route", "get", "8.8.8.8"], universal_newlines=True)
    except subprocess.CalledProcessError:
        expected_output = ""
    with open(route_file, "r") as f:
        actual_output = f.read()
    assert actual_output.strip() == expected_output.strip(), f"Content of {route_file} does not match the expected output of 'ip route get 8.8.8.8'."


def test_expect_script_exists_and_executable():
    script_path = "/home/user/trigger_sync.exp"
    assert os.path.isfile(script_path), f"Expect script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Expect script {script_path} is not executable."


def test_post_receive_hook_exists_and_executable():
    hook_path = "/home/user/iot_repo.git/hooks/post-receive"
    assert os.path.isfile(hook_path), f"Git hook {hook_path} does not exist."
    assert os.access(hook_path, os.X_OK), f"Git hook {hook_path} is not executable."


def test_device_sync_log():
    log_path = "/home/user/device_sync_log.txt"
    assert os.path.isfile(log_path), f"Device sync log {log_path} does not exist. The simulated IoT device was not notified correctly."
    with open(log_path, "r") as f:
        content = f.read().strip()
    expected_content = "SYNC_SUCCESS: /home/user/deploy_stage"
    assert content == expected_content, f"Expected device sync log to contain '{expected_content}', but got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$WORKDIR/test_final_state.py" -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
