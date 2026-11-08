#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import pathlib
import subprocess
import time
import urllib.error
import urllib.request
import uuid


def fetch(url="http://127.0.0.1:8000"):
    req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=5) as response:
        return response.getcode(), response.read().decode("utf-8")


def test_nginx_config_fixed():
    nginx_conf_path = "/home/user/nginx/nginx.conf"
    assert os.path.exists(nginx_conf_path), f"Nginx config not found at {nginx_conf_path}"
    with open(nginx_conf_path, "r") as f:
        content = f.read()
        assert "proxy_pass http://127.0.0.1:8080;" in content, "Nginx config was not updated to point to port 8080."


def test_symlink_and_directories():
    app_logs_dir = "/home/user/app_logs"
    app_logs_symlink = "/home/user/app/logs"

    assert os.path.isdir(app_logs_dir), f"Directory {app_logs_dir} does not exist."
    assert os.path.islink(app_logs_symlink), f"{app_logs_symlink} is not a symlink."

    target = os.readlink(app_logs_symlink)
    assert target == app_logs_dir, f"Symlink {app_logs_symlink} points to {target}, expected {app_logs_dir}."


def test_post_receive_hook():
    hook_path = "/home/user/repo.git/hooks/post-receive"
    assert os.path.exists(hook_path), f"Git hook not found at {hook_path}"
    assert os.access(hook_path, os.X_OK), f"Git hook at {hook_path} is not executable."


def test_startup_log_utc():
    log_path = "/home/user/app_logs/startup.log"
    assert os.path.exists(log_path), f"Startup log not found at {log_path}. Did the backend run successfully?"

    with open(log_path, "r") as f:
        content = f.read()
        assert "UTC" in content, "The startup log does not contain a UTC timestamp. Ensure TZ=UTC is set."


def test_nginx_response():
    url = "http://127.0.0.1:8000"
    try:
        status, body = fetch(url)
        assert status == 200, f"Expected HTTP 200, got {status}"
        assert "Backend running!" in body, f"Expected 'Backend running!' in response, got: {body}"
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to Nginx on port 8000: {e}"


def nginx_master_is_real():
    pid_path = "/home/user/nginx/nginx.pid"
    assert os.path.isfile(pid_path), "Nginx PID file is missing"
    pid = int(pathlib.Path(pid_path).read_text().strip())
    exe = os.path.realpath(f"/proc/{pid}/exe")
    cmdline = pathlib.Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
    assert os.path.basename(exe) == "nginx", f"PID {pid} is not nginx: {exe}"
    assert "/home/user/nginx/nginx.conf" in cmdline, f"Nginx was not started with the required configuration: {cmdline}"
    subprocess.run(["nginx", "-t", "-c", "/home/user/nginx/nginx.conf"], check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)


def listener_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = pathlib.Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            if fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                inodes.add(fields[9])
    result = set()
    for proc in pathlib.Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            for fd in (proc / "fd").iterdir():
                try:
                    target = os.readlink(fd)
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    result.add(int(proc.name))
        except OSError:
            pass
    return result


def wait_for_deployment(token, previous_pids, pushed_at):
    deadline = time.time() + 15
    last_error = None
    while time.time() < deadline:
        try:
            pids = listener_pids(8080)
            assert len(pids) == 1, f"Expected exactly one backend listener, found {pids}"
            pid = next(iter(pids))
            assert pid not in previous_pids, "The hook did not replace the old backend process"
            expected_exe = os.path.realpath("/home/user/app/backend")
            actual_exe = os.path.realpath(f"/proc/{pid}/exe")
            assert actual_exe == expected_exe, f"Port 8080 is served by {actual_exe}, not the deployed backend"
            for _ in range(3):
                status, body = fetch()
                assert status == 200
                assert token in body, f"Nginx did not return the newly pushed backend response: {body!r}"
                time.sleep(0.15)
            log = pathlib.Path("/home/user/app_logs/startup.log")
            assert log.stat().st_mtime >= pushed_at - 2, "The pushed backend did not refresh startup.log"
            assert "UTC" in log.read_text(), "The executed backend did not run date with TZ=UTC"
            return pids
        except Exception as exc:
            last_error = exc
            time.sleep(0.25)
    raise AssertionError(f"Deployment did not become healthy: {last_error}")


def backend_source(token):
    body = f"Backend running! {token}\n"
    source = r'''#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

int main() {
    const char *tz = std::getenv("TZ");
    const char *pv = std::getenv("PATH");
    if (!tz || std::string(tz) != "UTC" || !pv) return 20;
    std::string path(pv);
    bool usrbin = false, bin = false;
    size_t start = 0;
    while (true) {
        size_t end = path.find(':', start);
        std::string item = path.substr(start, end == std::string::npos ? end : end - start);
        if (item.empty() || item[0] != '/') return 21;
        if (item == "/usr/bin") usrbin = true;
        if (item == "/bin") bin = true;
        if (end == std::string::npos) break;
        start = end + 1;
    }
    if (!usrbin || !bin) return 22;
    std::ofstream probe("logs/startup.log", std::ios::app);
    if (!probe.is_open()) return 23;
    probe.close();
    if (std::system("date '+%a %b %d %T %Z %Y' > logs/startup.log") != 0) return 24;

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return 25;
    int opt = 1;
    if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt)) != 0) return 26;
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(8080);
    if (bind(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) return 27;
    if (listen(fd, 8) != 0) return 28;
    const std::string body = "__BODY__";
    const std::string response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: __LEN__\r\nConnection: close\r\n\r\n" + body;
    while (true) {
        int client = accept(fd, nullptr, nullptr);
        if (client < 0) continue;
        send(client, response.data(), response.size(), 0);
        close(client);
    }
}
'''
    return source.replace("__BODY__", body.replace("\n", "\\n")).replace("__LEN__", str(len(body.encode())))


def push_version(work, token, message):
    source = backend_source(token)
    (work / "server.cpp").write_text(source)
    subprocess.run(["git", "add", "server.cpp"], cwd=work, check=True)
    subprocess.run(["git", "commit", "-m", message], cwd=work, check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    pushed_at = time.time()
    subprocess.run(["git", "push", "origin", "HEAD:master"], cwd=work, check=True,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    return source, pushed_at


def test_zz_real_git_deployment_and_restart():
    nginx_master_is_real()
    work = pathlib.Path(f"/tmp/deploy-verifier-{uuid.uuid4().hex}")
    subprocess.run(["git", "-c", "safe.directory=*", "clone", "/home/user/repo.git", str(work)],
                   check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
    subprocess.run(["git", "config", "user.email", "verifier@example.invalid"], cwd=work, check=True)
    subprocess.run(["git", "config", "user.name", "Deployment Verifier"], cwd=work, check=True)

    old_pids = listener_pids(8080)
    token1 = "VERIFY_" + uuid.uuid4().hex
    source1, pushed1 = push_version(work, token1, "verifier deployment one")
    pids1 = wait_for_deployment(token1, old_pids, pushed1)

    deployed_source = pathlib.Path("/home/user/app/server.cpp")
    backend = pathlib.Path("/home/user/app/backend")
    assert deployed_source.read_text() == source1, "The hook did not check out the latest pushed source"
    assert backend.is_file() and os.access(backend, os.X_OK), "The hook did not compile an executable backend"
    assert backend.read_bytes()[:4] == b"\x7fELF", "The deployed backend is not a compiled ELF executable"

    token2 = "VERIFY_" + uuid.uuid4().hex
    source2, pushed2 = push_version(work, token2, "verifier deployment two")
    pids2 = wait_for_deployment(token2, pids1, pushed2)
    assert pids1.isdisjoint(pids2), "A second push did not restart the backend"
    assert deployed_source.read_text() == source2, "The second push was not checked out"

    status, body = fetch()
    assert status == 200 and token2 in body and token1 not in body, "Nginx is not proxying the current deployed backend"

    assert os.path.isdir("/home/user/app_logs")
    assert os.path.islink("/home/user/app/logs")
    assert os.readlink("/home/user/app/logs") == "/home/user/app_logs"

    remote_head = subprocess.check_output(
        ["git", "-c", "safe.directory=*", "--git-dir=/home/user/repo.git", "rev-parse", "refs/heads/master"],
        text=True).strip()
    local_head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=work, text=True).strip()
    assert remote_head == local_head, "The pushed revision is not the deployed repository's latest revision"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
