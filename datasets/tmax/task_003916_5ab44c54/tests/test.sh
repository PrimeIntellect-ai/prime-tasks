#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import tempfile
import pytest

AGENT_SCRIPT = "/home/user/generate_csp.sh"
PIN = "8492"


def generate_random_string(length=10):
    return ''.join(random.choices(string.ascii_letters, k=length))


def create_fuzz_env(base_dir):
    webroot = os.path.join(base_dir, "webroot")
    os.makedirs(webroot)

    num_dirs = random.randint(0, 15)
    for _ in range(num_dirs):
        dirname = generate_random_string(random.randint(3, 12))
        dirpath = os.path.join(webroot, dirname)
        os.makedirs(dirpath)

        mode = 0o755
        if random.random() < 0.3:
            mode |= 0o002
        if random.random() < 0.3:
            mode |= 0o1000
        os.chmod(dirpath, mode)

    header_file = os.path.join(base_dir, "headers.txt")
    headers = [
        "HTTP/1.1 200 OK",
        "Content-Type: text/html",
        f"Server: {generate_random_string()}",
        f"X-Random-Header: {generate_random_string()}"
    ]
    body = b"<html><body>" + generate_random_string(20).encode() + b"</body></html>\r\n"

    with open(header_file, "wb") as f:
        f.write(b"\r\n".join(h.encode() for h in headers))
        f.write(b"\r\n\r\n")
        f.write(body)

    return webroot, header_file


def expected_output(webroot, header_file):
    csp = "Content-Security-Policy: default-src 'self';"

    for dirname in sorted(os.listdir(webroot)):
        dirpath = os.path.join(webroot, dirname)
        if not os.path.isdir(dirpath):
            continue
        mode = os.stat(dirpath).st_mode
        if mode & 0o002:
            csp += f" script-src-elem 'none' /{dirname};"
        if mode & 0o1000:
            csp += " object-src 'none';"

    with open(header_file, "rb") as f:
        original = f.read()

    headers, separator, body = original.partition(b"\r\n\r\n")
    assert separator, "Test fixture is missing the header/body separator"
    return (headers + b"\r\n" + csp.encode() + b"\r\n" +
            f"X-Admin-Pin: {PIN}".encode() + b"\r\n\r\n" + body)


def run_agent(webroot, header_file):
    env = os.environ.copy()
    env["LC_ALL"] = "C"
    proc = subprocess.run(
        [AGENT_SCRIPT, webroot, header_file],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        env=env,
    )
    assert proc.returncode == 0, (
        f"Agent script exited with {proc.returncode}: "
        f"{proc.stderr.decode(errors='replace')}"
    )
    return proc.stdout


def test_script_exists_and_is_executable():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable"


def test_exact_permission_logic_without_duplicate_directives():
    with tempfile.TemporaryDirectory() as tmpdir:
        webroot = os.path.join(tmpdir, "webroot")
        os.makedirs(webroot)
        modes = {
            "a_world": 0o757,
            "b_sticky": 0o1755,
            "c_both": 0o1757,
            "d_group_writable_only": 0o775,
        }
        for name, mode in modes.items():
            path = os.path.join(webroot, name)
            os.makedirs(path)
            os.chmod(path, mode)

        header_file = os.path.join(tmpdir, "headers.txt")
        with open(header_file, "wb") as f:
            f.write(b"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\nbody\r\n")

        assert run_agent(webroot, header_file) == expected_output(webroot, header_file)


def test_fuzz_behavior():
    random.seed(42)
    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(100):
            env_dir = os.path.join(tmpdir, f"test_{i}")
            os.makedirs(env_dir)
            webroot, header_file = create_fuzz_env(env_dir)
            actual = run_agent(webroot, header_file)
            expected = expected_output(webroot, header_file)
            if actual != expected:
                dirs_info = []
                for name in sorted(os.listdir(webroot)):
                    path = os.path.join(webroot, name)
                    if os.path.isdir(path):
                        dirs_info.append(f"{name}: {oct(os.stat(path).st_mode & 0o7777)}")
                pytest.fail(
                    f"Mismatch on fuzz iteration {i}.\n"
                    f"Directories: {', '.join(dirs_info)}\n"
                    f"Expected bytes: {expected!r}\n"
                    f"Actual bytes:   {actual!r}"
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
