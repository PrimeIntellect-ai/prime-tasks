#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import socket
import subprocess
import time
import pytest

REPO = "/home/user/repo"
MAIN = f"{REPO}/main.cpp"
HOOK = f"{REPO}/.git/hooks/post-commit"
APP = f"{REPO}/app_bin"
LOG = "/home/user/deployment_output.log"
SECRET_FILE = "/tmp/secret.txt"


def run_as_user(command, timeout=30):
    return subprocess.run(
        ["su", "-s", "/bin/bash", "user", "-c", command],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )


def listener_owner_pids(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    owners = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.add(int(name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return owners


def request_secret_through_8080(expected):
    with socket.create_connection(("127.0.0.1", 8080), timeout=5) as sock:
        sock.sendall(b"GET /secret.txt HTTP/1.0\r\nHost: localhost\r\n\r\n")
        chunks = []
        while True:
            data = sock.recv(4096)
            if not data:
                break
            chunks.append(data)
    response = b"".join(chunks).decode("utf-8", errors="replace")
    assert expected in response, "Port 8080 did not retrieve the current data from the service on port 9090."


def test_deployment_output_log_exists_and_correct():
    assert os.path.isfile(LOG), f"Output log file {LOG} does not exist. The pipeline may not have run or failed."
    with open(LOG) as f:
        content = f.read()
    assert "SECRET_CONFIG_99281" in content, "The output log does not contain the expected secret 'SECRET_CONFIG_99281'."


def test_git_post_commit_hook_configured():
    assert os.path.isfile(HOOK), f"Git hook {HOOK} does not exist."
    assert os.access(HOOK, os.X_OK), f"Git hook {HOOK} is not executable."
    with open(HOOK) as f:
        content = f.read()
    assert "g++" in content, "The post-commit hook does not appear to compile the code using g++."
    assert "/home/user/repo/app_bin" in content, "The post-commit hook does not reference the expected binary path /home/user/repo/app_bin."


def test_git_commit_exists():
    try:
        output = subprocess.check_output(
            ["git", "log", "--format=%H%x09%s"], cwd=REPO,
            stderr=subprocess.STDOUT, text=True
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to run git log: {e.output}")

    matches = [line.split("\t", 1)[0] for line in output.splitlines()
               if "\t" in line and line.split("\t", 1)[1] == "Fix paths and harden deployment"]
    assert matches, "The required commit 'Fix paths and harden deployment' was not found in the git log."

    commit = matches[0]
    committed_main = subprocess.check_output(
        ["git", "show", f"{commit}:main.cpp"], cwd=REPO, text=True
    )
    assert "/home/user/deployment_output.log" in committed_main, "The required main.cpp change was not included in the named commit."
    changed = subprocess.check_output(
        ["git", "diff-tree", "--no-commit-id", "--name-only", "-r", commit],
        cwd=REPO, text=True
    ).splitlines()
    assert "main.cpp" in changed, "The named deployment commit did not commit a change to main.cpp."


def test_main_cpp_modified():
    assert os.path.isfile(MAIN), f"File {MAIN} does not exist."
    with open(MAIN) as f:
        content = f.read()
    assert "/home/user/deployment_output.log" in content, "main.cpp does not contain the expected absolute path '/home/user/deployment_output.log'."


def test_ssh_port_forwarding():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    result = sock.connect_ex(("127.0.0.1", 8080))
    sock.close()
    assert result == 0, "Port 8080 is not listening. The SSH tunnel may not be set up correctly."

    try:
        output = subprocess.check_output(["ps", "aux"], text=True)
        ssh_forwarding_found = any(
            "ssh" in line and "-L" in line and "8080" in line and "9090" in line
            for line in output.splitlines()
        )
        assert ssh_forwarding_found, "Could not find an ssh process running with local port forwarding for 8080 to 9090."
    except subprocess.CalledProcessError:
        pytest.fail("Failed to run ps aux to check for ssh port forwarding.")

    owners = listener_owner_pids(8080)
    real_ssh_owner = False
    for pid in owners:
        try:
            exe = os.path.realpath(f"/proc/{pid}/exe")
            cmd = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace")
        except (OSError, ProcessLookupError):
            continue
        if os.path.basename(exe) == "ssh" and "-L" in cmd and "8080" in cmd and "9090" in cmd:
            real_ssh_owner = True
            break
    assert real_ssh_owner, "Port 8080 is not owned by the configured SSH forwarding process."


def test_hook_pipeline_and_application_behavior():
    with open(MAIN) as f:
        original_source = f.read()

    marker = f"/tmp/hook_marker_{secrets.token_hex(10)}"
    nonce = f"DYNAMIC_CONFIG_{secrets.token_hex(20)}"
    marker_code = f'\n    std::ofstream verifier_marker("{marker}"); verifier_marker << "executed"; verifier_marker.close();\n'
    instrumented, count = re.subn(
        r"(\bint\s+main\s*\([^)]*\)\s*\{)",
        lambda m: m.group(1) + marker_code,
        original_source,
        count=1,
    )
    assert count == 1, "Could not instrument main.cpp to verify hook execution."

    try:
        with open(SECRET_FILE, "w") as f:
            f.write(nonce + "\n")
        request_secret_through_8080(nonce)

        with open(MAIN, "w") as f:
            f.write(instrumented)
        for path in (APP, LOG, marker):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        result = run_as_user("cd /home/user/repo && git commit --allow-empty -m 'Verifier pipeline exercise'")
        assert result.returncode == 0, f"Unable to trigger the post-commit pipeline:\n{result.stdout}"
        assert os.path.isfile(marker), "The post-commit hook did not execute the application compiled from main.cpp."
        assert os.path.isfile(APP) and os.access(APP, os.X_OK), "The hook did not create an executable app_bin."
        with open(APP, "rb") as f:
            assert f.read(4) == b"\x7fELF", "app_bin is not a compiled ELF executable."
        assert os.path.isfile(LOG), "The hook-triggered application did not create the deployment output log."
        with open(LOG) as f:
            assert nonce in f.read(), "The hook-triggered pipeline did not retrieve the dynamically selected configuration."

        second_nonce = f"RUNTIME_CONFIG_{secrets.token_hex(20)}"
        with open(SECRET_FILE, "w") as f:
            f.write(second_nonce + "\n")
        try:
            os.remove(LOG)
        except FileNotFoundError:
            pass
        stray = "/tmp/output.log"
        try:
            os.remove(stray)
        except FileNotFoundError:
            pass
        app_result = subprocess.run([APP], cwd="/tmp", stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
        assert app_result.returncode == 0, "The compiled application failed while the forwarded service was available."
        assert os.path.isfile(LOG), "The application did not use the required absolute output path when run from another directory."
        assert not os.path.exists(stray), "The application still wrote output.log relative to its working directory."
        with open(LOG) as f:
            assert second_nonce in f.read(), "The compiled application did not retrieve the current configuration through port 8080."
    finally:
        with open(MAIN, "w") as f:
            f.write(original_source)

    with open(MAIN, "w") as f:
        f.write("this is deliberately invalid C++\n")
    try:
        compile_failure = run_as_user("/home/user/repo/.git/hooks/post-commit")
        assert compile_failure.returncode != 0, "The hook did not return non-zero when compilation failed."
        assert "error" in compile_failure.stdout.lower(), "The hook did not echo an error when compilation failed."
    finally:
        with open(MAIN, "w") as f:
            f.write(original_source)

    owners = listener_owner_pids(8080)
    assert owners, "The port 8080 listener disappeared before connection-error testing."
    for pid in owners:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    deadline = time.time() + 5
    while time.time() < deadline:
        probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        unavailable = probe.connect_ex(("127.0.0.1", 8080)) != 0
        probe.close()
        if unavailable:
            break
        time.sleep(0.1)
    assert unavailable, "Could not stop the forwarding listener to test connection-error handling."

    direct_failure = subprocess.run([APP], cwd="/tmp", stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
    assert direct_failure.returncode != 0, "The compiled application returned success after its connection to localhost:8080 failed."

    hook_failure = run_as_user("/home/user/repo/.git/hooks/post-commit")
    assert hook_failure.returncode != 0, "The hook did not return non-zero when application execution failed."
    assert "error" in hook_failure.stdout.lower(), "The hook did not echo an error when application execution failed."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
