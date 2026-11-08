#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import socket
import subprocess
import tempfile
import time
import uuid


def exercise_server(executable):
    socket_path = f"/home/user/run/verifier_{uuid.uuid4().hex[:12]}.sock"
    env = os.environ.copy()
    env["UPSTREAM_SOCKET"] = socket_path
    proc = subprocess.Popen(
        [executable], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    try:
        deadline = time.time() + 5
        while not os.path.exists(socket_path):
            if proc.poll() is not None:
                out, err = proc.communicate()
                raise AssertionError(
                    f"Server exited before creating the full socket path: "
                    f"stdout={out!r}, stderr={err!r}"
                )
            if time.time() >= deadline:
                raise AssertionError(f"Server did not bind to {socket_path}")
            time.sleep(0.05)

        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        client.settimeout(3)
        try:
            client.connect(socket_path)
            received = b""
            while len(received) < 3:
                chunk = client.recv(16)
                if not chunk:
                    break
                received += chunk
        finally:
            client.close()

        assert received == b"OK\n", f"Server returned {received!r}, not b'OK\\n'"
        assert proc.wait(timeout=3) == 0, "Server did not exit successfully"
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        try:
            os.unlink(socket_path)
        except FileNotFoundError:
            pass


def test_server_c_fixed():
    """Test that server.c is fixed and that compiling it produces a working server."""
    server_c_path = '/home/user/app/server.c'
    assert os.path.isfile(server_c_path), f"File {server_c_path} does not exist."

    with open(server_c_path, 'r') as f:
        content = f.read()

    assert "strncpy(addr.sun_path, env_path, 10);" not in content, \
        "The bug (strncpy(..., 10)) is still present in server.c."
    assert "addr.sun_path" in content and "env_path" in content, \
        "Missing assignment to addr.sun_path from env_path."

    rebuilt = tempfile.NamedTemporaryFile(prefix="rebuilt_server_", delete=False)
    rebuilt.close()
    try:
        result = subprocess.run(
            ["gcc", server_c_path, "-o", rebuilt.name],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert result.returncode == 0, f"server.c does not compile with gcc: {result.stderr}"
        exercise_server(rebuilt.name)
    finally:
        try:
            os.unlink(rebuilt.name)
        except FileNotFoundError:
            pass


def test_server_compiled():
    """Test that the requested compiled server exists and actually works."""
    server_path = '/home/user/app/server'
    assert os.path.isfile(server_path), f"Executable {server_path} does not exist."
    assert os.access(server_path, os.X_OK), f"File {server_path} is not executable."
    with open(server_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "The server is not a compiled ELF executable."
    exercise_server(server_path)


def test_bashrc_exports():
    """Test that .bashrc contains the correct exports."""
    bashrc_path = '/home/user/.bashrc'
    assert os.path.isfile(bashrc_path), f"File {bashrc_path} does not exist."

    with open(bashrc_path, 'r') as f:
        content = f.read()

    assert re.search(r'export\s+UPSTREAM_SOCKET=[\'"]?/home/user/run/microservice\.sock[\'"]?', content), \
        "UPSTREAM_SOCKET export is missing or incorrect in .bashrc."
    assert re.search(r'export\s+TZ=[\'"]?Etc/UTC[\'"]?', content), \
        "TZ export is missing or incorrect in .bashrc."


def test_ci_test_sh_exists_and_executable():
    """Test that ci_test.sh exists, is executable, and has expected commands."""
    script_path = '/home/user/ci_test.sh'
    assert os.path.isfile(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

    with open(script_path, 'r') as f:
        content = f.read()

    assert ".bashrc" in content, "ci_test.sh does not source .bashrc."
    assert "server" in content, "ci_test.sh does not start the server."
    assert "nc -U" in content, "ci_test.sh does not use 'nc -U' to connect to the socket."
    assert "ci_result.log" in content, "ci_test.sh does not redirect output to ci_result.log."


def test_ci_script_runs_pipeline():
    """Execute the CI script and verify that it launches the server and nc in order."""
    script_path = '/home/user/ci_test.sh'
    server_path = '/home/user/app/server'
    expected_socket = '/home/user/run/microservice.sock'
    log_path = '/home/user/ci_result.log'
    token = uuid.uuid4().hex
    backup_server = f'/tmp/server_{token}'
    wrapper_dir = f'/tmp/ci_wrappers_{token}'
    server_marker = f'/tmp/server_marker_{token}'
    nc_marker = f'/tmp/nc_marker_{token}'

    os.makedirs('/home/user/run', exist_ok=True)
    for path in (expected_socket, log_path, server_marker, nc_marker):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    os.mkdir(wrapper_dir)
    os.replace(server_path, backup_server)
    try:
        with open(server_path, 'w') as f:
            f.write(
                '#!/bin/bash\n'
                f'printf "%s\\n%s\\n%s\\n" "$UPSTREAM_SOCKET" "$TZ" "$(date +%s%N)" > {server_marker}\n'
                f'exec {backup_server} "$@"\n'
            )
        os.chmod(server_path, 0o755)

        nc_wrapper = os.path.join(wrapper_dir, 'nc')
        with open(nc_wrapper, 'w') as f:
            f.write(
                '#!/bin/bash\n'
                f'printf "%s\\n" "$(date +%s%N)" "$@" > {nc_marker}\n'
                'exec /usr/bin/nc "$@"\n'
            )
        os.chmod(nc_wrapper, 0o755)

        env = {
            'HOME': '/home/user',
            'USER': 'user',
            'LOGNAME': 'user',
            'PATH': wrapper_dir + ':/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
        }
        result = subprocess.run(
            ['timeout', '15', script_path], env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert result.returncode == 0, \
            f"ci_test.sh failed: stdout={result.stdout!r}, stderr={result.stderr!r}"
        assert os.path.isfile(server_marker), "ci_test.sh did not start /home/user/app/server."
        assert os.path.isfile(nc_marker), "ci_test.sh did not execute nc from the configured PATH."

        with open(server_marker) as f:
            server_lines = f.read().splitlines()
        assert server_lines[0] == expected_socket, \
            "The server was not started with UPSTREAM_SOCKET loaded from .bashrc."
        assert server_lines[1] == 'Etc/UTC', \
            "The server was not started with TZ loaded from .bashrc."
        server_time = int(server_lines[2])

        with open(nc_marker) as f:
            nc_lines = f.read().splitlines()
        nc_time = int(nc_lines[0])
        assert nc_lines[1:] == ['-U', expected_socket], \
            f"Expected nc -U {expected_socket}, got arguments {nc_lines[1:]!r}."
        assert nc_time - server_time >= 800_000_000, \
            "ci_test.sh did not wait about one second after starting the server."
    finally:
        if os.path.exists(backup_server):
            os.replace(backup_server, server_path)
        shutil.rmtree(wrapper_dir, ignore_errors=True)
        for path in (server_marker, nc_marker, expected_socket):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass


def test_ci_result_log():
    """Test that the executed CI script produced the expected output."""
    log_path = '/home/user/ci_result.log'
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist. Did you run ci_test.sh?"

    with open(log_path, 'r') as f:
        content = f.read()

    assert content == "OK\n", f"Expected log content to be 'OK\\n', but got {repr(content)}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
