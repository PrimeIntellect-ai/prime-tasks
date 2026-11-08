#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'LAUNCH_EOF' > /tmp/no_child_exec.c
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ptrace.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 2) return 125;
    pid_t pid = fork();
    if (pid < 0) return 125;
    if (pid == 0) {
        if (ptrace(PTRACE_TRACEME, 0, NULL, NULL) < 0) _exit(125);
        raise(SIGSTOP);
        execl(argv[1], argv[1], (char *)NULL);
        _exit(127);
    }

    int status;
    if (waitpid(pid, &status, 0) < 0 || !WIFSTOPPED(status)) return 125;
    if (ptrace(PTRACE_SETOPTIONS, pid, NULL, (void *)PTRACE_O_TRACEEXEC) < 0) {
        kill(pid, SIGKILL);
        waitpid(pid, NULL, 0);
        return 125;
    }
    if (ptrace(PTRACE_CONT, pid, NULL, NULL) < 0) return 125;

    int exec_count = 0;
    for (;;) {
        if (waitpid(pid, &status, 0) < 0) return 125;
        if (WIFEXITED(status)) return WEXITSTATUS(status);
        if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
        if (!WIFSTOPPED(status)) continue;

        unsigned int event = ((unsigned int)status) >> 16;
        int sig = WSTOPSIG(status);
        if (event == PTRACE_EVENT_EXEC) {
            exec_count++;
            if (exec_count > 1) {
                ptrace(PTRACE_KILL, pid, NULL, NULL);
                waitpid(pid, NULL, 0);
                return 126;
            }
            sig = 0;
        } else if (sig == SIGTRAP || sig == SIGSTOP) {
            sig = 0;
        }
        if (ptrace(PTRACE_CONT, pid, NULL, (void *)(long)sig) < 0) return 125;
    }
}
LAUNCH_EOF
gcc -O2 /tmp/no_child_exec.c -o /tmp/no_child_exec
chmod 755 /tmp/no_child_exec

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import random
import re
import shlex
import socket
import subprocess
import tempfile
import threading


def test_ext4_image():
    img_path = "/home/user/data.img"
    assert os.path.exists(img_path), f"Missing image at {img_path}"

    size = os.path.getsize(img_path)
    assert 9 * 1024 * 1024 <= size <= 11 * 1024 * 1024, f"Image size {size} is not ~10MB"

    with open(img_path, "rb") as f:
        f.seek(0x438)
        magic = f.read(2)
        assert magic == b"\x53\xef", "File does not appear to be a valid ext2/3/4 filesystem (magic number mismatch)"


def test_data_mount_dir():
    mount_dir = "/home/user/data_mount"
    assert os.path.isdir(mount_dir), f"Missing mount directory at {mount_dir}"


def test_fstab_entry():
    fstab_path = "/home/user/fstab_entry"
    assert os.path.exists(fstab_path), f"Missing fstab entry file at {fstab_path}"
    with open(fstab_path, "r") as f:
        content = f.read().strip()

    parts = content.split()
    assert len(parts) >= 4, "fstab entry does not have enough fields"
    assert "/home/user/data.img" in parts[0] or "/home/user/data.img" in content, "fstab entry missing image path"
    assert "/home/user/data_mount" in parts[1] or "/home/user/data_mount" in content, "fstab entry missing mount point"
    assert "ext4" in parts[2] or "ext4" in content, "fstab entry missing ext4 filesystem type"


def test_sensor_env():
    env_path = "/home/user/sensor_env.sh"
    assert os.path.exists(env_path), f"Missing env script at {env_path}"
    with open(env_path, "r") as f:
        content = f.read()
    assert "Europe/Berlin" in content, "TZ environment variable is not set to Europe/Berlin"
    assert "en_US.UTF-8" in content, "LANG environment variable is not set to en_US.UTF-8"

    res = subprocess.run(
        ["/bin/bash", "--noprofile", "--norc", "-c", 'source "$1"; /usr/bin/env -0', "bash", env_path],
        capture_output=True,
        timeout=10,
    )
    assert res.returncode == 0, f"Environment script failed when sourced: {res.stderr!r}"
    env = {}
    for item in res.stdout.split(b"\0"):
        if b"=" in item:
            key, value = item.split(b"=", 1)
            env[key.decode(errors="replace")] = value.decode(errors="replace")
    assert env.get("TZ") == "Europe/Berlin", "sensor_env.sh must export TZ=Europe/Berlin"
    assert env.get("LANG") == "en_US.UTF-8", "sensor_env.sh must export LANG=en_US.UTF-8"


def _forward_spec(text):
    return re.search(r"(?:[^\s:]+:)?8080:(?:localhost|127\.0\.0\.1|\[::1\]):9090(?:\s|$)", text)


def test_ssh_tunnel_cmd():
    cmd_path = "/home/user/ssh_tunnel_cmd.txt"
    assert os.path.exists(cmd_path), f"Missing SSH tunnel command file at {cmd_path}"
    with open(cmd_path, "r") as f:
        content = f.read()
    assert "-L" in content, "SSH command missing -L flag for port forwarding"
    assert "8080" in content, "SSH command missing local port 8080"
    assert "9090" in content, "SSH command missing target port 9090"

    try:
        tokens = shlex.split(content)
    except ValueError as exc:
        raise AssertionError(f"Invalid SSH command syntax: {exc}")
    ssh_positions = [i for i, token in enumerate(tokens) if os.path.basename(token) == "ssh"]
    assert ssh_positions, "Command file does not contain an ssh invocation"
    ssh_args = tokens[ssh_positions[0]:]
    normalized = " ".join(ssh_args).replace("-L ", "-L")
    assert _forward_spec(normalized), "SSH command does not request local 8080 -> localhost:9090 forwarding"
    assert any(token == "localhost" or token.endswith("@localhost") for token in ssh_args), "SSH destination is not localhost"

    matching_processes = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            if args and os.path.basename(args[0]) == "ssh":
                process_text = " ".join(args).replace("-L ", "-L")
                if _forward_spec(process_text):
                    matching_processes.append((entry, args))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    assert matching_processes, "No running ssh process provides the requested port forward"

    ready = threading.Event()
    received = []
    nonce = os.urandom(32)

    def backend():
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("127.0.0.1", 9090))
        srv.listen(1)
        srv.settimeout(8)
        ready.set()
        try:
            conn, _ = srv.accept()
            with conn:
                conn.sendall(nonce)
                received.append(True)
        finally:
            srv.close()

    thread = threading.Thread(target=backend, daemon=True)
    thread.start()
    assert ready.wait(2), "Could not start tunnel backend test server"
    try:
        with socket.create_connection(("127.0.0.1", 8080), timeout=8) as client:
            client.settimeout(8)
            data = b""
            while len(data) < len(nonce):
                block = client.recv(len(nonce) - len(data))
                if not block:
                    break
                data += block
    except OSError as exc:
        raise AssertionError(f"Local port 8080 is not providing the requested SSH forwarding: {exc}")
    thread.join(9)
    assert received and data == nonce, "Traffic on port 8080 was not forwarded to localhost:9090"


def test_expect_script():
    script_path = "/home/user/automate_setup.exp"
    assert os.path.exists(script_path), f"Missing expect script at {script_path}"

    res = subprocess.run(["expect", script_path], capture_output=True, text=True, timeout=15)
    assert res.returncode == 0, f"Expect script failed with return code {res.returncode}. Output: {res.stdout}\n{res.stderr}"
    assert "Setup complete" in res.stdout, f"Expect script did not complete setup successfully. Output: {res.stdout}"


def _expected(inp):
    return base64.b64encode(inp[::-1].encode("ascii")) + b"\n"


def test_fuzz_equivalence():
    oracle = "/app/legacy_sensor_bin"
    agent = "/home/user/process_sensor"

    assert os.path.exists(agent), f"Agent program {agent} not found"
    assert os.access(agent, os.X_OK), f"Agent program {agent} is not executable"

    random.seed(42)
    chars = __import__("string").ascii_letters + __import__("string").digits + __import__("string").punctuation + " "
    cases = ["", "a", "abc", " ", "!~", "A" * 4095]
    for _ in range(100):
        length = random.randint(1, 100)
        cases.append("".join(random.choices(chars, k=length)))

    oracle_outputs = []
    for i, inp in enumerate(cases):
        oracle_proc = subprocess.run([oracle], input=(inp + "\n").encode("ascii"), capture_output=True, timeout=5)
        assert oracle_proc.returncode == 0, f"Oracle failed on input {inp!r}"
        expected = _expected(inp)
        assert oracle_proc.stdout == expected, f"Independent expected result disagrees with oracle on case {i}"
        oracle_outputs.append(oracle_proc.stdout)

    with open(oracle, "rb") as f:
        oracle_bytes = f.read()
    with open(agent, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Replacement program is a byte-identical copy of the legacy binary"
    assert not agent_bytes.startswith(oracle_bytes), "Replacement program is the legacy binary with appended data"

    private_dir = tempfile.mkdtemp(prefix="sensor-oracle-", dir="/root")
    hidden_oracle = os.path.join(private_dir, "legacy_sensor_bin")
    os.chmod(private_dir, 0o700)
    os.rename(oracle, hidden_oracle)
    try:
        for i, (inp, oracle_out) in enumerate(zip(cases, oracle_outputs)):
            agent_proc = subprocess.run(
                ["runuser", "-u", "user", "--", "/tmp/no_child_exec", agent],
                input=(inp + "\n").encode("ascii"),
                capture_output=True,
                timeout=5,
            )
            assert agent_proc.returncode == 0, (
                f"Agent failed on case {i} with return code {agent_proc.returncode}; "
                "the replacement must perform the transformation itself and may not execute the legacy binary"
            )
            agent_out = agent_proc.stdout
            assert oracle_out == agent_out, (
                f"Output mismatch on fuzz iteration {i}.\n"
                f"Input: {inp!r}\n"
                f"Oracle output: {oracle_out!r}\n"
                f"Agent output: {agent_out!r}"
            )
            assert agent_out == _expected(inp), f"Output does not match independently derived result on case {i}"
    finally:
        os.rename(hidden_oracle, oracle)
        os.rmdir(private_dir)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
