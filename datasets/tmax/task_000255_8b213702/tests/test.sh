#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import importlib.metadata
import os
import random
import re
import shutil
import socket
import stat
import subprocess
import tempfile
import time
import tomllib
import urllib.error
import urllib.request

import pytest
from packaging.requirements import Requirement
from packaging.version import Version

ORACLE = "/app/legacy_oracle"
WORKER = "/home/user/math_worker.sh"


def oracle_result(version, n):
    proc = subprocess.run(
        [ORACLE, version, str(n)], capture_output=True, text=True, timeout=5
    )
    assert proc.returncode == 0, f"Oracle failed on {version} {n}: {proc.stderr}"
    return proc.stdout.strip()


def copy_binary_and_libs(binary, root):
    destination = os.path.join(root, binary.lstrip("/"))
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    shutil.copy2(binary, destination)

    result = subprocess.run(["ldd", binary], capture_output=True, text=True)
    if result.returncode != 0:
        return
    for line in result.stdout.splitlines():
        matches = re.findall(r"(/[A-Za-z0-9_+.,@/-]+)", line)
        for library in matches:
            if os.path.isfile(library):
                target = os.path.join(root, library.lstrip("/"))
                os.makedirs(os.path.dirname(target), exist_ok=True)
                shutil.copy2(library, target)


@pytest.fixture(scope="session")
def worker_jail():
    root = tempfile.mkdtemp(prefix="worker-jail-")
    os.makedirs(os.path.join(root, "tmp"), mode=0o777)
    os.makedirs(os.path.join(root, "dev"), exist_ok=True)
    try:
        os.mknod(
            os.path.join(root, "dev", "null"),
            stat.S_IFCHR | 0o666,
            os.makedev(1, 3),
        )
    except FileExistsError:
        pass

    tools = [
        "/bin/bash", "/bin/cat", "/bin/echo", "/bin/grep", "/bin/sed",
        "/usr/bin/awk", "/usr/bin/cut", "/usr/bin/env", "/usr/bin/expr",
        "/usr/bin/grep", "/usr/bin/head", "/usr/bin/printf", "/usr/bin/seq",
        "/usr/bin/sed", "/usr/bin/tail", "/usr/bin/tr", "/usr/bin/wc",
    ]
    for tool in tools:
        if os.path.isfile(tool):
            copy_binary_and_libs(tool, root)

    os.makedirs(os.path.join(root, "bin"), exist_ok=True)
    if not os.path.exists(os.path.join(root, "bin", "sh")):
        shutil.copy2(os.path.join(root, "bin", "bash"), os.path.join(root, "bin", "sh"))

    shutil.copy2(WORKER, os.path.join(root, "worker.sh"))
    os.chmod(os.path.join(root, "worker.sh"), 0o755)
    yield root
    shutil.rmtree(root, ignore_errors=True)


def run_jailed_worker(root, version, n):
    uid = subprocess.check_output(["id", "-u", "user"], text=True).strip()
    gid = subprocess.check_output(["id", "-g", "user"], text=True).strip()
    proc = subprocess.run(
        [
            "chroot", f"--userspec={uid}:{gid}", root,
            "/bin/bash", "/worker.sh", version, str(n),
        ],
        capture_output=True,
        text=True,
        timeout=5,
        env={"PATH": "/bin:/usr/bin", "HOME": "/tmp"},
    )
    assert proc.returncode == 0, (
        f"Agent script failed on input {version} {n}. Stderr: {proc.stderr}"
    )
    return proc.stdout.strip()


def wait_for_port(port, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.2)
            if sock.connect_ex(("127.0.0.1", port)) == 0:
                return
        time.sleep(0.1)
    pytest.fail(f"Port {port} did not become ready")


def stop_port(port):
    subprocess.run(
        ["fuser", "-k", f"{port}/tcp"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    time.sleep(0.2)


def test_math_worker_exists_and_executable():
    assert os.path.isfile(WORKER), f"Agent script {WORKER} does not exist"
    assert os.access(WORKER, os.X_OK), f"Agent script {WORKER} is not executable"
    with open(WORKER, "rb") as handle:
        data = handle.read()
    assert not data.startswith(b"\x7fELF"), "math_worker.sh must be a Bash script, not a binary"
    text = data.decode("utf-8")
    assert re.match(r"^#!.*\b(bash|env +bash)\b", text.splitlines()[0]), (
        "math_worker.sh must have a Bash shebang"
    )
    assert "legacy_oracle" not in text, "math_worker.sh must not invoke the legacy oracle"


def test_fuzz_equivalence(worker_jail):
    assert os.path.isfile(ORACLE), f"Oracle {ORACLE} missing"
    random.seed(42)
    for _ in range(500):
        major = random.randint(0, 20)
        minor = random.randint(0, 20)
        patch = random.randint(0, 20)
        semver = f"{major}.{minor}.{patch}"
        n = random.randint(1, 10000)
        expected = oracle_result(semver, n)
        actual = run_jailed_worker(worker_jail, semver, n)
        assert actual == expected, (
            f"Mismatch on input '{semver}' '{n}'. "
            f"Oracle output: '{expected}', Agent output: '{actual}'"
        )


def test_package_configuration_and_install():
    path = "/app/backend/pyproject.toml"
    assert os.path.isfile(path), f"Missing {path}"
    with open(path, "rb") as handle:
        config = tomllib.load(handle)

    dependencies = config.get("project", {}).get("dependencies", [])
    parsed = [Requirement(item) for item in dependencies]
    names = {req.name.lower().replace("_", "-"): req for req in parsed}
    assert "legacy-math-ext" not in names, "legacy-math-ext must be removed"
    assert "flask" in names, "Flask must remain a project dependency"
    assert "redis" in names, "redis must remain a project dependency"

    proc = subprocess.run(
        ["python3", "-m", "pip", "install", "/app/backend"],
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert proc.returncode == 0, f"pip install . failed:\n{proc.stdout}\n{proc.stderr}"
    assert Version(importlib.metadata.version("flask")) >= Version("2.0")
    assert Version(importlib.metadata.version("redis")) >= Version("4.0")


def test_backend_and_nginx_configuration():
    app_text = open("/app/backend/app.py", encoding="utf-8").read()
    assert "legacy_math_ext" not in app_text, "Backend still imports the legacy extension"
    assert "subprocess" in app_text, "Backend must use subprocess"
    assert "/home/user/math_worker.sh" in app_text, "Backend must execute math_worker.sh"

    nginx_text = open("/app/nginx/nginx.conf", encoding="utf-8").read()
    assert re.search(r"listen\s+8080\s*;", nginx_text), "Nginx must listen on port 8080"
    assert re.search(r"location\s+(?:=\s*)?/api/math", nginx_text), (
        "Nginx must configure /api/math"
    )
    assert re.search(r"proxy_pass\s+http://(?:127\.0\.0\.1|localhost):5000", nginx_text), (
        "Nginx must proxy to Flask on port 5000"
    )
    check = subprocess.run(
        ["nginx", "-t", "-c", "/app/nginx/nginx.conf"],
        capture_output=True,
        text=True,
    )
    assert check.returncode == 0, f"Invalid Nginx configuration: {check.stderr}"


def test_end_to_end_api_and_redis():
    for port in (8080, 5000, 6379):
        stop_port(port)

    original = open(WORKER, "rb").read()
    verified_copy = "/tmp/verified_math_worker.sh"
    marker = "/tmp/math_worker_calls.log"
    with open(verified_copy, "wb") as handle:
        handle.write(original)
    os.chmod(verified_copy, 0o755)
    try:
        os.unlink(marker)
    except FileNotFoundError:
        pass

    wrapper = f'''#!/bin/bash
printf '%s\\t%s\\n' "$1" "$2" >> {marker}
exec /bin/bash {verified_copy} "$@"
'''
    with open(WORKER, "w", encoding="utf-8") as handle:
        handle.write(wrapper)
    os.chmod(WORKER, 0o755)

    redis_proc = flask_proc = nginx_proc = None
    old_mode = stat.S_IMODE(os.stat(ORACLE).st_mode)
    os.chmod(ORACLE, 0o700)
    try:
        redis_proc = subprocess.Popen(
            ["redis-server", "--port", "6379", "--save", "", "--appendonly", "no"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        wait_for_port(6379)

        flask_proc = subprocess.Popen(
            ["runuser", "-u", "user", "--", "python3", "/app/backend/app.py"],
            cwd="/app/backend",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env={**os.environ, "PYTHONUNBUFFERED": "1"},
        )
        wait_for_port(5000)

        nginx_proc = subprocess.Popen(
            ["nginx", "-c", "/app/nginx/nginx.conf", "-g", "daemon off;"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        wait_for_port(8080)

        assert redis_proc.poll() is None, "Redis exited unexpectedly"
        assert flask_proc.poll() is None, "Flask exited unexpectedly"
        assert nginx_proc.poll() is None, "Nginx exited unexpectedly"

        v, n = "2.4.1", 42
        expected = oracle_result(v, n)
        assert expected == "367"
        url = f"http://127.0.0.1:8080/api/math?v={v}&n={n}"
        try:
            with urllib.request.urlopen(url, timeout=5) as response:
                status = response.getcode()
                body = response.read().decode("utf-8").strip()
        except urllib.error.URLError as exc:
            pytest.fail(f"Failed through Nginx -> Flask: {exc}")

        assert status == 200
        assert body == expected, f"Expected API result {expected}, got {body}"
        assert os.path.isfile(marker), "Backend did not execute /home/user/math_worker.sh"
        assert "2.4.1\t42" in open(marker, encoding="utf-8").read()

        sock = socket.create_connection(("127.0.0.1", 6379), timeout=2)
        sock.sendall(b"*2\r\n$3\r\nGET\r\n$8\r\n2.4.1:42\r\n")
        redis_response = sock.recv(1024).decode("utf-8")
        sock.close()
        assert "367" in redis_response, (
            f"Expected cached value '367' for 2.4.1:42, got {redis_response!r}"
        )
    finally:
        with open(WORKER, "wb") as handle:
            handle.write(original)
        os.chmod(WORKER, 0o755)
        os.chmod(ORACLE, old_mode)
        for proc in (nginx_proc, flask_proc, redis_proc):
            if proc is not None and proc.poll() is None:
                proc.terminate()
        for proc in (nginx_proc, flask_proc, redis_proc):
            if proc is not None:
                try:
                    proc.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    proc.kill()
        for port in (8080, 5000, 6379):
            stop_port(port)
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
