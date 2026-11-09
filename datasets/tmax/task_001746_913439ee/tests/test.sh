#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pwd
import re
import secrets
import shutil
import stat
import subprocess
import tempfile
import urllib.parse
import urllib.request

PROJECT = "/home/user/project"
APP = "/home/user/project/build/src/app"
EXPECTED = b"Pipeline success. 5 * 6 = 30\n"


def fetch(port, expr):
    url = f"http://127.0.0.1:{port}/evaluate?" + urllib.parse.urlencode({"expr": expr})
    with urllib.request.urlopen(url, timeout=5) as response:
        assert response.status == 200
        data = json.loads(response.read().decode("utf-8"))
    assert isinstance(data, dict), f"Expected a JSON object for {expr}, got {data!r}"
    assert isinstance(data.get("build"), bool), f"Missing boolean build value for {expr}: {data!r}"
    return data


def listening_socket_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def nginx_processes():
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            exe = os.path.realpath(f"/proc/{entry}/exe")
            if os.path.basename(exe) != "nginx":
                continue
            uid = os.stat(f"/proc/{entry}").st_uid
            raw = open(f"/proc/{entry}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
            found.append((entry, uid, raw))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return found


def test_cmake_fixed_and_builds():
    # Preserve the original configuration assertion.
    src_cmake = "/home/user/project/src/CMakeLists.txt"
    root_cmake = "/home/user/project/CMakeLists.txt"
    fixed = False
    for path in [src_cmake, root_cmake]:
        if os.path.isfile(path):
            with open(path) as f:
                content = f.read()
            if "target_link_libraries" in content and "custom_math" in content:
                fixed = True
                break
    assert fixed, "CMakeLists.txt was not fixed. Could not find 'target_link_libraries' linking 'custom_math'."

    # Configure and compile from scratch, then verify the produced ELF really uses the library.
    build = tempfile.mkdtemp(prefix="verifier-cmake-", dir="/tmp")
    try:
        subprocess.run(["cmake", "-S", PROJECT, "-B", build], check=True, timeout=60)
        subprocess.run(["cmake", "--build", build, "--parallel", "2"], check=True, timeout=60)
        binary = os.path.join(build, "src", "app")
        assert os.path.isfile(binary) and os.access(binary, os.X_OK), "CMake did not produce an executable app"
        with open(binary, "rb") as f:
            assert f.read(4) == b"\x7fELF", "The built app is not an ELF executable"
        linked = subprocess.run(["ldd", binary], check=True, text=True, capture_output=True).stdout
        assert "libcustom_math.so" in linked and "not found" not in linked, f"app is not correctly linked to custom_math:\n{linked}"
        result = subprocess.run([binary], check=True, capture_output=True, timeout=10)
        assert result.stdout == EXPECTED, f"Unexpected app output: {result.stdout!r}"
    finally:
        shutil.rmtree(build, ignore_errors=True)


def test_nginx_is_real_and_non_root():
    config = "/home/user/nginx.conf"
    assert os.path.isfile(config), "Missing /home/user/nginx.conf"
    content = open(config).read()
    assert re.search(r"\blisten\s+127\.0\.0\.1:8080\s*;", content), "Nginx must listen on 127.0.0.1:8080"
    assert re.search(r"\bproxy_pass\s+http://127\.0\.0\.1:5000/?\s*;", content), "Nginx must proxy to 127.0.0.1:5000"
    for directive in ("pid", "error_log", "access_log", "client_body_temp_path", "proxy_temp_path"):
        assert re.search(rf"\b{directive}\s+/tmp/nginx/", content), f"{directive} must use /tmp/nginx/"

    user_uid = pwd.getpwnam("user").pw_uid
    processes = nginx_processes()
    assert processes, "Nginx is not running"
    assert any(uid == user_uid for _, uid, _ in processes), "Nginx is not running as the non-root user"

    # Confirm an nginx process, rather than an arbitrary fake server, owns port 8080.
    inodes = listening_socket_inodes(8080)
    assert inodes, "Nothing is listening on port 8080"
    owns_listener = False
    for pid, uid, _ in processes:
        try:
            for fd in os.listdir(f"/proc/{pid}/fd"):
                try:
                    target = os.readlink(f"/proc/{pid}/fd/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes and uid == user_uid:
                    owns_listener = True
        except (FileNotFoundError, PermissionError):
            pass
    assert owns_listener, "Port 8080 is not owned by the non-root Nginx process"

    # Verify the running master was launched with the requested configuration.
    uses_config = False
    for pid, _, command in processes:
        if "master process" not in command or "-c" not in command:
            continue
        words = command.split()
        try:
            supplied = words[words.index("-c") + 1]
            if not os.path.isabs(supplied):
                supplied = os.path.join(os.path.realpath(f"/proc/{pid}/cwd"), supplied)
            if os.path.realpath(supplied) == os.path.realpath(config):
                uses_config = True
        except (ValueError, IndexError, FileNotFoundError):
            pass
    assert uses_config, "The running Nginx master was not started with /home/user/nginx.conf"


def test_api_and_nginx():
    assert os.path.isfile("/home/user/evaluator/app.py"), "Missing evaluator/app.py"

    # Preserve the original two API assertions.
    assert fetch(8080, "5>3").get("build") is True
    assert fetch(8080, "5<3").get("build") is False

    # Exercise unpredictable arithmetic inequalities through both the service and proxy.
    for index in range(20):
        a = secrets.randbelow(80) + 2
        b = secrets.randbelow(20) + 1
        arithmetic = secrets.choice(["+", "-", "*"])
        value = {"+": a + b, "-": a - b, "*": a * b}[arithmetic]
        expected = index % 2 == 0
        comparison = secrets.choice([">", "<"])
        if comparison == ">":
            right = value - 1 if expected else value + 1
        else:
            right = value + 1 if expected else value - 1
        expr = f"{a}{arithmetic}{b}{comparison}{right}"
        direct = fetch(5000, expr)
        proxied = fetch(8080, expr)
        assert direct.get("build") is expected, f"Wrong direct result for {expr}: {direct}"
        assert proxied.get("build") is expected, f"Wrong proxied result for {expr}: {proxied}"


def test_pipeline_script_and_output():
    script = "/home/user/run_pipeline.sh"
    assert os.path.isfile(script), "Missing /home/user/run_pipeline.sh"
    mode = os.stat(script).st_mode
    assert mode & stat.S_IXUSR, "run_pipeline.sh is not executable"
    script_content = open(script).read()
    assert re.search(r"\bcurl\b", script_content), "Pipeline script must use curl"
    assert "http://127.0.0.1:8080/evaluate?expr=7*2%3E10" in script_content, "Pipeline script does not request the required URL"

    # Remove all prior artifacts so a prewritten output file or prebuilt app cannot pass.
    shutil.rmtree("/home/user/project/build", ignore_errors=True)
    try:
        os.remove("/home/user/pipeline_output.txt")
    except FileNotFoundError:
        pass

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    subprocess.run(["runuser", "-u", "user", "--", script], check=True, timeout=120, env=env)

    assert os.path.isfile(APP) and os.access(APP, os.X_OK), "Pipeline did not build app at the required path"
    with open(APP, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Pipeline app is not an ELF executable"
    linked = subprocess.run(["ldd", APP], check=True, text=True, capture_output=True).stdout
    assert "libcustom_math.so" in linked and "not found" not in linked, f"Pipeline app is not linked correctly:\n{linked}"

    output_file = "/home/user/pipeline_output.txt"
    assert os.path.isfile(output_file), f"Pipeline output file {output_file} is missing. Did the script run?"
    output = open(output_file, "rb").read()

    # Preserve the original output assertion, then require exact captured stdout.
    assert "Pipeline success. 5 * 6 = 30" in output.decode(errors="replace")
    actual = subprocess.run([APP], check=True, capture_output=True, timeout=10).stdout
    assert output == actual == EXPECTED, f"pipeline_output.txt is not the exact app stdout: {output!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
