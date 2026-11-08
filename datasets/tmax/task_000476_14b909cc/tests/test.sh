#!/bin/bash
set +e
mkdir -p /logs/verifier
prep_failed=0

cat > /tmp/redirect_bind.c <<'EOF'
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <dlfcn.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>

typedef int (*bind_fn)(int, const struct sockaddr *, socklen_t);

int bind(int fd, const struct sockaddr *addr, socklen_t len) {
    static bind_fn real_bind;
    struct sockaddr_in copy;
    if (!real_bind)
        real_bind = (bind_fn)dlsym(RTLD_NEXT, "bind");
    if (addr && addr->sa_family == AF_INET && len >= sizeof(copy)) {
        memcpy(&copy, addr, sizeof(copy));
        if (ntohs(copy.sin_port) == 8888)
            copy.sin_port = htons(18888);
        return real_bind(fd, (const struct sockaddr *)&copy, sizeof(copy));
    }
    return real_bind(fd, addr, len);
}
EOF

gcc -shared -fPIC -o /tmp/redirect_bind.so /tmp/redirect_bind.c -ldl || prep_failed=1
if [ -f /home/user/secure_auth_server.c ]; then
    gcc -o /tmp/submission_secure_auth_server /home/user/secure_auth_server.c -lcrypto -lseccomp || prep_failed=1
else
    prep_failed=1
fi

cat > /tmp/probe_seccomp.c <<'EOF'
#define _GNU_SOURCE
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ptrace.h>
#include <sys/types.h>
#include <sys/user.h>
#include <sys/wait.h>
#include <unistd.h>
#include <asm/unistd.h>
#include <linux/ptrace.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    pid_t pid = (pid_t)strtol(argv[1], NULL, 10);
    int status;
    int changed = 0;

    if (ptrace(PTRACE_ATTACH, pid, 0, 0) == -1) return 3;
    if (waitpid(pid, &status, 0) == -1 || !WIFSTOPPED(status)) return 4;
    if (ptrace(PTRACE_SETOPTIONS, pid, 0, PTRACE_O_TRACESYSGOOD) == -1) return 5;
    if (ptrace(PTRACE_SYSCALL, pid, 0, 0) == -1) return 6;

    for (int i = 0; i < 100; i++) {
        if (waitpid(pid, &status, 0) == -1) return changed ? 0 : 7;
        if (WIFEXITED(status) || WIFSIGNALED(status))
            return changed ? 0 : 8;
        if (!WIFSTOPPED(status)) return 9;

        int sig = WSTOPSIG(status);
        if (sig == SIGSYS && changed) {
            ptrace(PTRACE_KILL, pid, 0, 0);
            return 0;
        }

        if (sig == (SIGTRAP | 0x80)) {
            struct ptrace_syscall_info info;
            long n = ptrace(PTRACE_GET_SYSCALL_INFO, pid, sizeof(info), &info);
            if (n < 0) return 10;

            if (!changed && info.op == PTRACE_SYSCALL_INFO_ENTRY) {
                struct user_regs_struct regs;
                if (ptrace(PTRACE_GETREGS, pid, 0, &regs) == -1) return 11;
                regs.orig_rax = __NR_execve;
                if (ptrace(PTRACE_SETREGS, pid, 0, &regs) == -1) return 12;
                changed = 1;
            } else if (changed && info.op == PTRACE_SYSCALL_INFO_EXIT) {
                long rv = (long)info.exit.rval;
                ptrace(PTRACE_DETACH, pid, 0, 0);
                /* With execve allowed, the deliberately invalid pathname is EFAULT. */
                if (rv == -EFAULT) return 13;
                return rv < 0 ? 0 : 14;
            }
        }

        int deliver = (sig == (SIGTRAP | 0x80) || sig == SIGSTOP || sig == SIGTRAP) ? 0 : sig;
        if (ptrace(PTRACE_SYSCALL, pid, 0, deliver) == -1)
            return changed ? 0 : 15;
    }
    ptrace(PTRACE_DETACH, pid, 0, 0);
    return 16;
}
EOF

gcc -o /tmp/probe_seccomp /tmp/probe_seccomp.c || prep_failed=1

copy_pid=""
if [ "$prep_failed" -eq 0 ]; then
    LD_PRELOAD=/tmp/redirect_bind.so /tmp/submission_secure_auth_server >/tmp/submission_server.log 2>&1 &
    copy_pid=$!
fi
export COPY_SERVER_PID="$copy_pid"
export PREP_FAILED="$prep_failed"

cat > /tmp/test_final_state.py <<'PYEOF'
import hashlib
import os
import random
import re
import socket
import string
import subprocess
import time

SOURCE = "/home/user/secure_auth_server.c"
BINARY = "/home/user/secure_auth_server"


def recover_expected_token():
    text = subprocess.check_output(
        ["tesseract", "/app/admin_note.png", "stdout"],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    match = re.search(r"BASE\s*:\s*([A-Za-z0-9]{4})", text, re.IGNORECASE)
    assert match, f"OCR did not recover a BASE value from the supplied image: {text!r}"
    base = match.group(1)
    target = "c4efd5020cb49b9d3257ffa0fbccc0ff"
    matches = []
    for a in string.ascii_lowercase:
        for b in string.ascii_lowercase:
            candidate = base + a + b
            if hashlib.md5(candidate.encode()).hexdigest() == target:
                matches.append(candidate)
    assert len(matches) == 1, f"Expected one matching token, found {len(matches)}"
    return matches[0]


TOKEN = recover_expected_token()


def send_and_receive(port, payload, timeout=3.0):
    if isinstance(payload, str):
        payload = payload.encode()
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout)
        sock.connect(("127.0.0.1", port))
        sock.sendall(payload)
        response = b""
        while b"\n" not in response:
            part = sock.recv(1024)
            if not part:
                break
            response += part
        return response


def wait_for_port(port, timeout=5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise AssertionError(f"No server began listening on 127.0.0.1:{port}")


def listener_pids(port):
    wanted = f"{port:04X}"
    inodes = set()
    with open("/proc/net/tcp") as f:
        next(f)
        for line in f:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            if local.endswith(":" + wanted) and state == "0A":
                inodes.add(fields[9])
    result = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", link)
                if match and match.group(1) in inodes:
                    result.add(int(name))
                    break
        except OSError:
            pass
    return result


def test_c_source_and_binary_exist_and_use_seccomp():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing"
    assert os.path.isfile(BINARY), f"Compiled server {BINARY} is missing"
    assert os.access(BINARY, os.X_OK), f"Compiled server {BINARY} is not executable"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The deployed server is not an ELF executable"
    content = open(SOURCE, errors="replace").read()
    uses_seccomp = any(keyword in content for keyword in (
        "seccomp_init", "seccomp_load", "seccomp_rule_add",
        "PR_SET_SECCOMP", "SECCOMP_MODE_STRICT", "SECCOMP_MODE_FILTER",
    ))
    assert uses_seccomp, "Source code is missing the required seccomp implementation"
    assert TOKEN not in content, "The recovered six-character token is hardcoded in the source"
    assert TOKEN.encode() not in open(BINARY, "rb").read(), "The recovered token is embedded literally in the binary"


def test_deployed_listener_is_compiled_artifact():
    wait_for_port(8888)
    pids = listener_pids(8888)
    assert pids, "No process owns a listening socket on TCP port 8888"
    deployed = os.stat(BINARY)
    assert any(
        os.stat(f"/proc/{pid}/exe").st_ino == deployed.st_ino and
        os.stat(f"/proc/{pid}/exe").st_dev == deployed.st_dev
        for pid in pids
    ), "The process listening on port 8888 is not /home/user/secure_auth_server"


def check_protocol(port):
    assert send_and_receive(port, TOKEN + "\n") == b"GRANTED\n"
    assert send_and_receive(port, TOKEN) == b"GRANTED\n"

    rng = random.SystemRandom()
    invalid = {"", "invalid", TOKEN[:-1], TOKEN + "x", TOKEN.swapcase()}
    while len(invalid) < 45:
        length = rng.randint(1, 32)
        value = "".join(rng.choice(string.ascii_letters + string.digits) for _ in range(length))
        if value != TOKEN:
            invalid.add(value)
    for value in invalid:
        assert send_and_receive(port, value + "\n") == b"DENIED\n", value


def test_deployed_server_protocol():
    check_protocol(8888)


def test_recompiled_submission_protocol():
    assert os.environ.get("PREP_FAILED") == "0", "The submitted C source did not compile"
    pid = int(os.environ["COPY_SERVER_PID"])
    assert os.path.exists(f"/proc/{pid}"), "The verifier-built server exited prematurely"
    wait_for_port(18888)
    check_protocol(18888)


def test_z_seccomp_filter_really_blocks_execve():
    pid = int(os.environ["COPY_SERVER_PID"])
    status = open(f"/proc/{pid}/status").read()
    match = re.search(r"^Seccomp:\s*(\d+)$", status, re.MULTILINE)
    assert match and match.group(1) == "2", "The running server did not install a seccomp filter"
    result = subprocess.run(["/tmp/probe_seccomp", str(pid)], capture_output=True, text=True)
    assert result.returncode == 0, (
        "An execve syscall was not blocked by the running server's seccomp policy "
        f"(probe exit {result.returncode})"
    )
PYEOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short
result=$?

if [ -n "$copy_pid" ]; then
    kill "$copy_pid" 2>/dev/null || true
    wait "$copy_pid" 2>/dev/null || true
fi

if [ "$result" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
