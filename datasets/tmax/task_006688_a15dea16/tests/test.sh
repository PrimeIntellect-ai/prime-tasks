#!/bin/bash
set -e
mkdir -p /logs/verifier

TAR_VERIFY_REAL=/usr/bin/tar.verifier-real
TAR_VERIFY_LOG=/tmp/prov-shim-tar.log
export TAR_VERIFY_REAL TAR_VERIFY_LOG
rm -f "$TAR_VERIFY_LOG" "$TAR_VERIFY_REAL"
mv /usr/bin/tar "$TAR_VERIFY_REAL"
cat > /usr/bin/tar <<'WRAPPER_EOF'
#!/bin/bash
{
    printf '%s\037' "$@"
    printf '\n'
} >> "$TAR_VERIFY_LOG"
exec "$TAR_VERIFY_REAL" "$@"
WRAPPER_EOF
chmod 755 /usr/bin/tar
restore_tar() {
    rm -f /usr/bin/tar
    if [ -e "$TAR_VERIFY_REAL" ]; then
        mv "$TAR_VERIFY_REAL" /usr/bin/tar
    fi
}
trap restore_tar EXIT

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import socket
import subprocess
import time
import urllib.request
import uuid

BINARY = "/home/user/prov-shim/target/release/prov-shim"
TAR_LOG = "/tmp/prov-shim-tar.log"


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def expected_gateway():
    with open("/proc/net/route", "r") as route_file:
        lines = route_file.readlines()
    for line in lines[1:]:
        parts = line.split()
        if len(parts) >= 3 and parts[1] == "00000000":
            return parts[2]
    assert False, "Could not find default gateway (Destination 00000000) in /proc/net/route"


def child_pids(pid):
    path = f"/proc/{pid}/task/{pid}/children"
    try:
        with open(path, "r") as children_file:
            return [int(value) for value in children_file.read().split()]
    except (FileNotFoundError, ProcessLookupError):
        return []


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as command_file:
            return [part.decode(errors="replace") for part in command_file.read().split(b"\0") if part]
    except (FileNotFoundError, ProcessLookupError):
        return []


def read_tar_invocations():
    try:
        with open(TAR_LOG, "r") as log_file:
            return [[arg for arg in line.rstrip("\n").split("\x1f") if arg] for line in log_file]
    except FileNotFoundError:
        return []


def is_expected_server(argv, port, workspace):
    if len(argv) != 6:
        return False
    return (
        os.path.basename(argv[0]).startswith("python3")
        and argv[1:3] == ["-m", "http.server"]
        and argv[3] == str(port)
        and argv[4:] == ["--directory", workspace]
    )


def assert_tar_command(invocations, workspace, backup):
    matching = [args for args in invocations if workspace in args and backup in args]
    assert matching, "The shim did not execute system tar with the requested workspace and backup paths"
    options = " ".join(matching[0])
    has_create = "--create" in options or any(arg.startswith("-") and "c" in arg for arg in matching[0])
    has_gzip = "--gzip" in options or any(arg.startswith("-") and "z" in arg for arg in matching[0])
    has_file = "--file" in options or any(arg.startswith("-") and "f" in arg for arg in matching[0])
    assert has_create and has_gzip and has_file, f"tar was not invoked to create a gzipped archive: {matching[0]}"


def test_prov_shim_binary_exists():
    assert os.path.exists(BINARY), f"Rust binary not found at {BINARY}. Did you compile in release mode?"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), f"File at {BINARY} is not an executable."
    with open(BINARY, "rb") as binary_file:
        assert binary_file.read(4) == b"\x7fELF", "The release artifact must be a compiled native executable"

    manifest = "/home/user/prov-shim/Cargo.toml"
    source = "/home/user/prov-shim/src/main.rs"
    assert os.path.isfile(manifest), "Cargo.toml is missing from the Rust project"
    assert os.path.isfile(source), "src/main.rs is missing from the Rust project"
    with open(source, "r", errors="replace") as source_file:
        source_text = source_file.read()
    assert "Command" in source_text and "tar" in source_text, "Rust source must invoke tar through std::process::Command"


def exercise_once(run_number):
    token = uuid.uuid4().hex
    base = f"/home/user/shim-eval-{run_number}-{token}"
    workspace = os.path.join(base, "workspace data")
    backup = os.path.join(base, "backup output.tar.gz")
    extracted_dir = os.path.join(base, "extracted")
    port = free_port()
    challenge_name = f"challenge-{token}.txt"
    challenge_data = f"dynamic-{uuid.uuid4().hex}"

    if os.path.exists(base):
        shutil.rmtree(base)
    os.makedirs(base)
    open(TAR_LOG, "w").close()

    start_time = time.monotonic()
    proc = subprocess.Popen(
        [BINARY, workspace, str(port), backup],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    server_pid = None
    server_seen_at = None
    request_succeeded = False
    tar_seen_while_server_alive = False
    deadline = start_time + 10.0

    while time.monotonic() < deadline and proc.poll() is None:
        for pid in child_pids(proc.pid):
            argv = cmdline(pid)
            if is_expected_server(argv, port, workspace):
                server_pid = pid
                if server_seen_at is None:
                    server_seen_at = time.monotonic()
                break

        if server_pid is not None and os.path.isdir(workspace) and not request_succeeded:
            status_path = os.path.join(workspace, "status.txt")
            gateway_path = os.path.join(workspace, "gateway.info")
            if os.path.isfile(status_path) and os.path.isfile(gateway_path):
                with open(status_path, "r") as status_file:
                    assert status_file.read().strip() == "RUNNING"
                with open(gateway_path, "r") as gateway_file:
                    assert gateway_file.read().strip() == expected_gateway()
                with open(os.path.join(workspace, challenge_name), "w") as challenge_file:
                    challenge_file.write(challenge_data)
                try:
                    with urllib.request.urlopen(
                        f"http://127.0.0.1:{port}/{challenge_name}", timeout=0.4
                    ) as response:
                        request_succeeded = response.status == 200 and response.read().decode() == challenge_data
                except Exception:
                    pass

        if read_tar_invocations() and server_pid is not None and os.path.exists(f"/proc/{server_pid}"):
            tar_seen_while_server_alive = True
        time.sleep(0.025)

    if proc.poll() is None:
        proc.kill()
        proc.wait()
        assert False, "The shim program timed out (ran for more than 10 seconds). It should run for exactly 5 seconds."

    stdout, stderr = proc.communicate()
    elapsed = time.monotonic() - start_time

    assert proc.returncode == 0, f"Shim executed with non-zero exit code. STDERR:\n{stderr}"
    assert elapsed >= 5.0, f"Shim did not wait for the required 5 seconds. Elapsed time: {elapsed:.2f}s"
    assert elapsed < 8.0, f"Shim ran substantially longer than the required 5 seconds. Elapsed time: {elapsed:.2f}s"
    assert server_pid is not None, "No direct child running 'python3 -m http.server <port> --directory <workspace>' was observed"
    assert server_seen_at - start_time < 3.0, "The HTTP server was not started promptly"
    assert request_succeeded, "The required Python HTTP server did not serve the dynamic workspace content"
    assert not os.path.exists(f"/proc/{server_pid}"), "The HTTP server child was not terminated and reaped"
    assert not tar_seen_while_server_alive, "The backup was started before the HTTP server terminated"

    invocations = read_tar_invocations()
    assert_tar_command(invocations, workspace, backup)
    assert os.path.exists(backup), f"Backup tarball not created at {backup}"

    os.makedirs(extracted_dir)
    extract_proc = subprocess.run(
        ["tar", "-xzf", backup, "-C", extracted_dir], capture_output=True, text=True
    )
    assert extract_proc.returncode == 0, f"Failed to extract backup tarball. STDERR:\n{extract_proc.stderr}"

    status_file = os.path.join(extracted_dir, "status.txt")
    assert os.path.exists(status_file), "status.txt not found in the backup archive"
    with open(status_file, "r") as status_handle:
        status_content = status_handle.read().strip()
    assert status_content == "RUNNING", f"Expected status.txt to contain 'RUNNING', but got '{status_content}'"

    gateway_file = os.path.join(extracted_dir, "gateway.info")
    assert os.path.exists(gateway_file), "gateway.info not found in the backup archive"
    with open(gateway_file, "r") as gateway_handle:
        actual_gateway = gateway_handle.read().strip()
    assert actual_gateway == expected_gateway(), f"Gateway mismatch in gateway.info: expected '{expected_gateway()}', got '{actual_gateway}'"

    archived_challenge = os.path.join(extracted_dir, challenge_name)
    assert os.path.isfile(archived_challenge), "The tarball did not contain the entire dynamically modified workspace"
    with open(archived_challenge, "r") as challenge_file:
        assert challenge_file.read() == challenge_data

    shutil.rmtree(base)


def test_prov_shim_execution_and_artifacts():
    exercise_once(1)
    exercise_once(2)


def test_rejects_wrong_argument_counts():
    for args in ([], ["one", "two", "three", "four"]):
        try:
            result = subprocess.run([BINARY] + args, capture_output=True, text=True, timeout=2)
        except subprocess.TimeoutExpired:
            assert False, f"Shim did not promptly reject an invalid argument count: {len(args)}"
        assert result.returncode != 0, f"Shim accepted {len(args)} arguments instead of exactly three"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
