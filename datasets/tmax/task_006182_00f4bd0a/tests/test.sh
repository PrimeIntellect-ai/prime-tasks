#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import glob
import http.client
import os
import random
import re
import signal
import string
import subprocess
import time
import urllib.error
import urllib.request

import pytest

ROOT = "/home/user/waf-proxy"
DEBUG_EXE = ROOT + "/build_debug/waf_server"
RELEASE_EXE = ROOT + "/build_release/waf_server"


def test_test_results_log():
    log_path = "/home/user/test_results.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.read().strip().splitlines() if line.strip()]

    assert len(lines) >= 2, f"{log_path} does not contain enough lines"
    assert lines[0] == "200", f"Expected first line of {log_path} to be '200', got '{lines[0]}'"
    assert lines[1] == "403", f"Expected second line of {log_path} to be '403', got '{lines[1]}'"


def test_build_directories():
    for exe in (DEBUG_EXE, RELEASE_EXE):
        assert os.path.isfile(exe), f"Executable not found at {exe}"
        assert os.access(exe, os.X_OK), f"File at {exe} is not executable"
        with open(exe, "rb") as f:
            assert f.read(4) == b"\x7fELF", f"{exe} is not an ELF executable"


def test_memory_leak_fixed_source_check():
    waf_cpp_path = ROOT + "/waf.cpp"
    assert os.path.isfile(waf_cpp_path), f"File {waf_cpp_path} does not exist"
    with open(waf_cpp_path, "r") as f:
        content = f.read()

    leak_fixed = "delete" in content or "new int[100]" not in content or "unique_ptr" in content
    assert leak_fixed, "Memory leak in waf.cpp does not appear to be fixed (no 'delete' found and 'new' still present)"


def test_original_fixed_endpoints():
    safe_url = "http://127.0.0.1:8080/api/safe"
    try:
        with urllib.request.urlopen(urllib.request.Request(safe_url), timeout=2) as response:
            assert response.getcode() == 200
    except Exception as e:
        pytest.fail(f"Failed safe endpoint check: {e}")

    hack_url = "http://127.0.0.1:8080/api/hack?q=UNION%20SELECT"
    try:
        urllib.request.urlopen(urllib.request.Request(hack_url), timeout=2)
        pytest.fail("Expected 403 Forbidden")
    except urllib.error.HTTPError as e:
        assert e.code == 403
    except Exception as e:
        pytest.fail(f"Failed blocked endpoint check: {e}")


def listening_inodes(port):
    result = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    cols = line.split()
                    if len(cols) >= 10 and cols[3] == "0A":
                        if int(cols[1].split(":")[-1], 16) == port:
                            result.add(cols[9])
        except FileNotFoundError:
            pass
    return result


def owners_of_inodes(inodes):
    owners = set()
    for procdir in glob.glob("/proc/[0-9]*"):
        pid = int(procdir.rsplit("/", 1)[1])
        try:
            for fd in os.listdir(procdir + "/fd"):
                try:
                    link = os.readlink(procdir + "/fd/" + fd)
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    owners.add(pid)
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return owners


def kill_port(port):
    pids = owners_of_inodes(listening_inodes(port))
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while time.time() < deadline and listening_inodes(port):
        time.sleep(0.05)
    for pid in owners_of_inodes(listening_inodes(port)):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listening_inodes(port):
        time.sleep(0.05)
    assert not listening_inodes(port), f"Could not free TCP port {port}"


def wait_for_exact_listener(proc, executable, port):
    deadline = time.time() + 6
    wanted = os.path.realpath(executable)
    while time.time() < deadline:
        if proc.poll() is not None:
            pytest.fail(f"{executable} exited prematurely with status {proc.returncode}")
        owners = owners_of_inodes(listening_inodes(port))
        if proc.pid in owners:
            assert os.path.realpath(f"/proc/{proc.pid}/exe") == wanted
            return
        time.sleep(0.05)
    pytest.fail(f"{executable} did not listen on port {port}")


def request_status(port, path):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
    try:
        conn.request("GET", path, headers={"Connection": "close"})
        response = conn.getresponse()
        response.read()
        return response.status
    finally:
        conn.close()


def start_server(executable, asan=False):
    env = os.environ.copy()
    if asan:
        env["ASAN_OPTIONS"] = "detect_leaks=0:abort_on_error=1"
    proc = subprocess.Popen(
        [executable], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, env=env, start_new_session=True
    )
    wait_for_exact_listener(proc, executable, 9000)
    return proc


def stop_server(proc):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def randomized_cases():
    token = "".join(random.SystemRandom().choice(string.ascii_letters) for _ in range(18))
    blocked = [
        f"/api/{token}/UNION%20SELECT/end",
        f"/api/{token}?v=prefixUNION%20SELECTsuffix",
        f"/api/{token}?a={token}&b=UNION%20SELECT",
    ]
    allowed = [
        f"/api/{token}/normal",
        f"/api/{token}?v=union%20select",
        f"/api/{token}?v=UNION%20%20SELECT",
        f"/api/{token}?v=UNIONXSELECT",
        f"/api/{token}?v=SELECT%20UNION",
    ]
    return blocked, allowed


def test_cmake_configuration_and_real_builds():
    cmake_file = ROOT + "/CMakeLists.txt"
    assert os.path.isfile(cmake_file), "CMakeLists.txt is missing"

    for directory, expected in ((ROOT + "/build_debug", "ON"), (ROOT + "/build_release", "OFF")):
        cache = directory + "/CMakeCache.txt"
        assert os.path.isfile(cache), f"Missing CMake cache in {directory}"
        cache_text = open(cache, errors="replace").read()
        assert re.search(rf"^ENABLE_ASAN:[^=]*={expected}$", cache_text, re.MULTILINE), \
            f"{directory} was not configured with ENABLE_ASAN={expected}"

    temp_root = "/tmp/verifier-cmake"
    subprocess.run(["rm", "-rf", temp_root], check=True)
    os.makedirs(temp_root)
    builds = []
    for name, value in (("debug", "ON"), ("release", "OFF")):
        build = os.path.join(temp_root, name)
        subprocess.run(
            ["cmake", "-S", ROOT, "-B", build, f"-DENABLE_ASAN={value}"],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30
        )
        subprocess.run(
            ["cmake", "--build", build, "--target", "waf_server", "-j2"],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=45
        )
        exe = build + "/waf_server"
        assert os.path.isfile(exe) and os.access(exe, os.X_OK)
        assert open(exe, "rb").read(4) == b"\x7fELF"
        metadata = "\n".join(
            open(p, errors="replace").read()
            for p in glob.glob(build + "/**/*", recursive=True)
            if os.path.isfile(p) and (p.endswith("flags.make") or p.endswith("link.txt") or p.endswith("build.make"))
        )
        assert "waf.cpp" in metadata, "waf_server is not built from waf.cpp"
        if value == "ON":
            assert "-fsanitize=address" in metadata, "ASAN build lacks -fsanitize=address"
            assert re.search(r"(^|\s)-g(\s|$)", metadata), "ASAN build lacks -g"
        else:
            assert re.search(r"(^|\s)-O2(\s|$)", metadata), "Release build lacks -O2"
        builds.append(exe)


def test_dynamic_memory_safety():
    harness = r'''#define main waf_original_main
#include "/home/user/waf-proxy/waf.cpp"
#undef main
#include <sys/socket.h>
#include <unistd.h>
#include <string>
int main() {
    for (int i = 0; i < 40; ++i) {
        int sv[2];
        if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) return 2;
        std::string req = "GET /api/memory-check HTTP/1.1\r\nHost: local\r\n\r\n";
        if (write(sv[0], req.data(), req.size()) < 0) return 3;
        shutdown(sv[0], SHUT_WR);
        handle_client(sv[1]);
        char reply[256];
        ssize_t n = read(sv[0], reply, sizeof(reply));
        close(sv[0]);
        if (n <= 0 || std::string(reply, n).find("200") == std::string::npos) return 4;
    }
    return 0;
}
'''
    source = "/tmp/waf_leak_harness.cpp"
    binary = "/tmp/waf_leak_harness"
    open(source, "w").write(harness)
    subprocess.run(["g++", "-std=c++11", "-pthread", source, "-o", binary], check=True, timeout=30)
    result = subprocess.run(
        ["valgrind", "--quiet", "--leak-check=full", "--show-leak-kinds=definite",
         "--errors-for-leak-kinds=definite", "--error-exitcode=77", binary],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, "Valgrind found a definite memory leak:\n" + result.stderr


def test_nginx_real_proxy_and_built_servers():
    config = "/home/user/nginx.conf"
    assert os.path.isfile(config), "Nginx configuration is missing"
    checked = subprocess.run(
        ["nginx", "-T", "-c", config], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, timeout=10
    )
    assert checked.returncode == 0, checked.stdout
    rendered = checked.stdout
    assert re.search(r"\blisten\s+[^;]*\b8080\b[^;]*;", rendered), "Nginx does not listen on 8080"
    assert re.search(r"location\s+(?:\^~\s+)?/api/\s*\{", rendered), "Missing /api/ location"
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:9000\s*;", rendered), \
        "The /api/ proxy is not directed to 127.0.0.1:9000"

    nginx_owners = owners_of_inodes(listening_inodes(8080))
    assert nginx_owners, "Nothing is listening on port 8080"
    assert any(
        os.path.basename(os.path.realpath(f"/proc/{pid}/exe")) == "nginx"
        for pid in nginx_owners if os.path.exists(f"/proc/{pid}/exe")
    ), "Port 8080 is not owned by Nginx"
    nginx_cmdlines = []
    for procdir in glob.glob("/proc/[0-9]*"):
        try:
            if os.path.basename(os.path.realpath(procdir + "/exe")) == "nginx":
                nginx_cmdlines.append(open(procdir + "/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace"))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    assert any(config in cmd for cmd in nginx_cmdlines), "Running Nginx was not started with /home/user/nginx.conf"

    kill_port(9000)
    debug = start_server(DEBUG_EXE, asan=True)
    try:
        blocked, allowed = randomized_cases()
        for path in allowed:
            assert request_status(9000, path) == 200
        for path in blocked:
            assert request_status(9000, path) == 403
    finally:
        stop_server(debug)

    kill_port(9000)
    release = start_server(RELEASE_EXE)
    blocked, allowed = randomized_cases()
    for path in allowed:
        assert request_status(9000, path) == 200, f"Release backend rejected safe URI {path}"
        assert request_status(8080, path) == 200, f"Nginx failed to proxy safe URI {path}"
    for path in blocked:
        assert request_status(9000, path) == 403, f"Release backend allowed attack URI {path}"
        assert request_status(8080, path) == 403, f"Nginx failed to proxy blocked URI {path}"

    assert release.poll() is None, "Release waf_server is not still running"
    assert owners_of_inodes(listening_inodes(9000)) == {release.pid}, \
        "The release waf_server is not the backend listener on port 9000"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
