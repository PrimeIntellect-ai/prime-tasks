#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import socket
import subprocess
import threading


def free_bytes():
    info = os.statvfs("/home/user/data_dir")
    return info.f_bavail * info.f_frsize


def capture_report(command, fixed_port=0, use_profile=False):
    received = []
    observed_free = []

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", fixed_port))
    port = listener.getsockname()[1]
    listener.listen(1)
    listener.settimeout(5)

    def receive():
        try:
            conn, _ = listener.accept()
            observed_free.append(free_bytes())
            with conn:
                conn.settimeout(5)
                chunks = []
                while True:
                    chunk = conn.recv(1024)
                    if not chunk:
                        break
                    chunks.append(chunk)
                received.append(b"".join(chunks))
        finally:
            listener.close()

    thread = threading.Thread(target=receive)
    thread.start()

    env = os.environ.copy()
    if use_profile:
        env.pop("REPORTER_HOST", None)
        env.pop("REPORTER_PORT", None)
    else:
        env["REPORTER_HOST"] = "127.0.0.1"
        env["REPORTER_PORT"] = str(port)

    before = free_bytes()
    result = subprocess.run(command, capture_output=True, text=True, env=env, timeout=10)
    after = free_bytes()
    thread.join(timeout=6)
    assert not thread.is_alive(), "Listener did not finish."
    return result, received, {before, after, *observed_free}


def assert_valid_report(result, received, expected_values):
    assert result.returncode == 0, (
        f"Reporter exited with {result.returncode}; stderr was {result.stderr!r}"
    )
    assert received, "No data received from the reporter."
    assert len(received) == 1, "Expected exactly one TCP connection."

    try:
        output = received[0].decode("utf-8")
    except UnicodeDecodeError as exc:
        raise AssertionError("Reporter payload was not valid UTF-8/ASCII") from exc

    # Preserve the original format assertion.
    match = re.match(r"^DATA_DIR_FREE_BYTES:(\d+)\n?$", output)
    assert match, (
        "Received data format is incorrect. Expected "
        f"'DATA_DIR_FREE_BYTES:<bytes>\\n', got {output!r}"
    )

    claimed = int(match.group(1))
    assert claimed in expected_values, (
        f"Reported {claimed} free bytes, but statvfs observed "
        f"{sorted(expected_values)} for /home/user/data_dir"
    )
    assert output == f"DATA_DIR_FREE_BYTES:{claimed}\n", (
        f"Payload was not the exact required string: {output!r}"
    )


def test_data_dir_exists():
    path = "/home/user/data_dir"
    assert os.path.isdir(path), f"{path} does not exist."


def test_c_file_exists():
    path = "/home/user/health_reporter.c"
    assert os.path.isfile(path), f"{path} does not exist."


def test_executable_exists():
    path = "/home/user/health_reporter"
    assert os.path.isfile(path), f"{path} does not exist."
    assert os.access(path, os.X_OK), f"{path} is not executable."
    with open(path, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", f"{path} is not a compiled ELF executable."


def test_bash_profile_exports():
    path = "/home/user/.bash_profile"
    assert os.path.isfile(path), f"{path} does not exist."
    with open(path, "r") as profile:
        content = profile.read()
    assert "REPORTER_HOST=127.0.0.1" in content, "REPORTER_HOST=127.0.0.1 not found in .bash_profile"
    assert "REPORTER_PORT=8888" in content, "REPORTER_PORT=8888 not found in .bash_profile"


def test_run_sh_exists_and_executable():
    path = "/home/user/run.sh"
    assert os.path.isfile(path), f"{path} does not exist."
    assert os.access(path, os.X_OK), f"{path} is not executable."
    with open(path, "r") as wrapper:
        content = wrapper.read()
    assert ".bash_profile" in content, "run.sh does not seem to source .bash_profile"
    assert "health_reporter" in content, "run.sh does not seem to execute health_reporter"


def test_end_to_end_reporting():
    result, received, expected = capture_report(
        ["bash", "/home/user/run.sh"], fixed_port=8888, use_profile=True
    )
    assert_valid_report(result, received, expected)


def test_source_compiles_and_behaves():
    rebuilt = "/tmp/health_reporter_rebuilt"
    build = subprocess.run(
        ["gcc", "-O2", "/home/user/health_reporter.c", "-o", rebuilt],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert build.returncode == 0, f"C source failed to compile: {build.stderr}"
    result, received, expected = capture_report([rebuilt])
    assert_valid_report(result, received, expected)


def test_missing_environment_variables_fail():
    cases = [
        ({"REPORTER_PORT": "8888"}, 8888),
        ({"REPORTER_HOST": "127.0.0.1"}, 8888),
    ]
    for supplied, port in cases:
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", port))
        listener.listen(1)
        try:
            env = os.environ.copy()
            env.pop("REPORTER_HOST", None)
            env.pop("REPORTER_PORT", None)
            env.update(supplied)
            result = subprocess.run(
                ["/home/user/health_reporter"],
                capture_output=True,
                text=True,
                env=env,
                timeout=5,
            )
        finally:
            listener.close()
        assert result.returncode == 1, (
            f"Reporter must exit 1 when an environment variable is missing; got {result.returncode}"
        )
        assert result.stderr, "Reporter must print an error to stderr when configuration is missing."


def test_connection_refused_fails():
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.bind(("127.0.0.1", 0))
    unused_port = probe.getsockname()[1]
    probe.close()

    env = os.environ.copy()
    env["REPORTER_HOST"] = "127.0.0.1"
    env["REPORTER_PORT"] = str(unused_port)
    result = subprocess.run(
        ["/home/user/health_reporter"],
        capture_output=True,
        text=True,
        env=env,
        timeout=5,
    )
    assert result.returncode == 1, (
        f"Reporter must exit 1 when connection is refused; got {result.returncode}"
    )
    assert result.stderr, "Reporter must print an error to stderr when connection fails."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
