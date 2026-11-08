#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PROBE_EOF' > /tmp/seccomp_probe.c
#define _GNU_SOURCE
#include <seccomp.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static void log_line(const char *line) {
    const char *path = getenv("SANDBOX_PROBE_LOG");
    if (!path) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        dprintf(fd, "%s\n", line);
        close(fd);
    }
}

scmp_filter_ctx seccomp_init(uint32_t def_action) {
    static scmp_filter_ctx (*real_fn)(uint32_t);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "seccomp_init");
    char line[64];
    snprintf(line, sizeof(line), "INIT %u", def_action);
    log_line(line);
    return real_fn(def_action);
}

int seccomp_load(const scmp_filter_ctx ctx) {
    static int (*real_fn)(const scmp_filter_ctx);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "seccomp_load");
    log_line("LOAD");
    return real_fn(ctx);
}

int execv(const char *path, char *const argv[]) {
    static int (*real_fn)(const char *, char *const []);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "execv");
    char line[1024];
    const char *arg1 = (argv && argv[1]) ? argv[1] : "<none>";
    snprintf(line, sizeof(line), "EXEC %s ARG1 %s", path ? path : "<null>", arg1);
    log_line(line);
    return real_fn(path, argv);
}
PROBE_EOF

gcc -shared -fPIC -o /tmp/seccomp_probe.so /tmp/seccomp_probe.c -ldl -lseccomp

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import platform
import subprocess
import tempfile

EXPECTED_SOURCE = b'''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>

void compliance_flag_reached() {
    FILE *f = fopen("/home/user/audit_flag.txt", "w");
    if (f) {
        fprintf(f, "COMPLIANCE_AUDIT_PASSED_XYZ123\\n");
        fclose(f);
    }
    printf("Compliance flag generated.\\n");
    exit(0);
}

void process_log_entry() {
    char buffer[64];
    printf("Enter log entry: ");
    gets(buffer); // VULNERABILITY: Buffer overflow
    printf("Logged: %s\\n", buffer);
}

int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "test_net") == 0) {
        // Dummy socket call to test seccomp sandbox
        int s = socket(AF_INET, SOCK_STREAM, 0);
        if (s < 0) {
            printf("Socket blocked!\\n");
            exit(1);
        }
        printf("Socket allowed!\\n");
        exit(0);
    }
    process_log_entry();
    return 0;
}
'''

FLAG = "/home/user/audit_flag.txt"
DAEMON_SOURCE = "/home/user/legacy_auditd.c"
DAEMON = "/home/user/legacy_auditd"
PAYLOAD = "/home/user/payload.bin"
SANDBOX_SOURCE = "/home/user/sandbox.c"
SANDBOX = "/home/user/sandbox"
PROBE = "/tmp/seccomp_probe.so"


def run(cmd, **kwargs):
    return subprocess.run(cmd, timeout=10, **kwargs)


def test_all_phases():
    # Preserve the supplied vulnerable daemon and rebuild it with the required flags.
    assert os.path.isfile(DAEMON_SOURCE), "legacy_auditd.c is missing"
    with open(DAEMON_SOURCE, "rb") as f:
        assert f.read() == EXPECTED_SOURCE, "Constraint failed: legacy_auditd.c was modified"
    build = run([
        "gcc", "-O0", "-fno-stack-protector", "-no-pie",
        "-o", DAEMON, DAEMON_SOURCE,
    ], capture_output=True, text=True)
    assert build.returncode == 0, f"Phase 1 Failed: daemon compilation failed: {build.stderr}"

    # Remove any pre-created flag, then exercise the submitted payload against the
    # freshly rebuilt daemon. Merely writing the known flag can no longer pass.
    assert os.path.isfile(PAYLOAD), "Phase 1 Failed: /home/user/payload.bin does not exist"
    assert os.path.getsize(PAYLOAD) > 0, "Phase 1 Failed: payload.bin is empty"
    try:
        os.unlink(FLAG)
    except FileNotFoundError:
        pass

    with open(PAYLOAD, "rb") as payload:
        exploit = run(
            ["setarch", platform.machine(), "-R", DAEMON],
            stdin=payload, capture_output=True,
        )

    # Some container runtimes prohibit setarch's personality operation even for
    # root. The non-PIE ret2win remains deterministic, so retry directly only when
    # setarch itself was denied.
    if not os.path.exists(FLAG) and exploit.returncode != 0 and b"Operation not permitted" in exploit.stderr:
        with open(PAYLOAD, "rb") as payload:
            exploit = run([DAEMON], stdin=payload, capture_output=True)

    output = exploit.stdout.decode(errors="replace")
    assert exploit.returncode == 0, f"Phase 1 Failed: exploit execution returned {exploit.returncode}"
    assert "Compliance flag generated." in output, "Phase 1 Failed: payload did not reach compliance_flag_reached()"
    assert os.path.exists(FLAG), "Phase 1 Failed: exploit did not create audit_flag.txt"
    with open(FLAG, "r") as f:
        assert f.read().strip() == "COMPLIANCE_AUDIT_PASSED_XYZ123", "Phase 1 Failed: audit flag content is incorrect"

    # Retain the original AES-256-CBC decryption assertion.
    enc_path = "/home/user/audit_trail.enc"
    assert os.path.exists(enc_path), "Phase 2 Failed: /home/user/audit_trail.enc does not exist"
    key = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    iv = "00112233445566778899aabbccddeeff"
    decrypted = run([
        "openssl", "enc", "-d", "-aes-256-cbc", "-K", key, "-iv", iv,
        "-in", enc_path,
    ], capture_output=True, text=True)
    assert decrypted.returncode == 0, f"Phase 2 Failed: decryption failed: {decrypted.stderr}"
    assert decrypted.stdout.strip() == "COMPLIANCE_AUDIT_PASSED_XYZ123", "Phase 2 Failed: decrypted content is incorrect"

    # Retain the executable checks and additionally require compilable C source.
    assert os.path.exists(SANDBOX), "Phase 3 Failed: /home/user/sandbox does not exist"
    assert os.access(SANDBOX, os.X_OK), "Phase 3 Failed: /home/user/sandbox is not executable"
    assert os.path.isfile(SANDBOX_SOURCE), "Phase 3 Failed: /home/user/sandbox.c does not exist"
    rebuilt = "/tmp/submitted_sandbox_rebuilt"
    build = run(["gcc", "-O2", "-o", rebuilt, SANDBOX_SOURCE, "-lseccomp"], capture_output=True, text=True)
    assert build.returncode == 0, f"Phase 3 Failed: sandbox.c does not compile with libseccomp: {build.stderr}"

    # Test both the submitted executable and a fresh build from its submitted source.
    for candidate in (SANDBOX, rebuilt):
        # A normal daemon execution must be reached and complete successfully.
        normal_log = tempfile.mktemp(prefix="sandbox-normal-")
        env = os.environ.copy()
        env["LD_PRELOAD"] = PROBE
        env["SANDBOX_PROBE_LOG"] = normal_log
        normal = run([candidate], input="verification_log_entry\n", capture_output=True, text=True, env=env)
        assert normal.returncode == 0, f"Phase 3 Failed: {candidate} cannot normally run the daemon"
        assert "Logged: verification_log_entry" in normal.stdout, f"Phase 3 Failed: {candidate} did not run the daemon on standard input"
        with open(normal_log, "r") as f:
            normal_trace = f.read()
        assert "INIT 2147418112" in normal_trace, "Phase 3 Failed: seccomp default action is not SCMP_ACT_ALLOW"
        assert "LOAD" in normal_trace, "Phase 3 Failed: the seccomp filter was not loaded"
        assert "EXEC /home/user/legacy_auditd ARG1 <none>" in normal_trace, "Phase 3 Failed: sandbox did not use execv on the daemon"

        # The same real exec path must forward test_net, while seccomp blocks socket.
        net_log = tempfile.mktemp(prefix="sandbox-net-")
        env["SANDBOX_PROBE_LOG"] = net_log
        net = run([candidate, "test_net"], capture_output=True, text=True, env=env)
        assert "Socket allowed!" not in net.stdout, "Phase 3 Failed: socket was allowed"
        assert net.returncode != 0 or "Socket blocked!" in net.stdout, "Phase 3 Failed: socket was not effectively blocked"
        with open(net_log, "r") as f:
            net_trace = f.read()
        assert "INIT 2147418112" in net_trace, "Phase 3 Failed: seccomp default action is not SCMP_ACT_ALLOW"
        assert "LOAD" in net_trace, "Phase 3 Failed: the seccomp filter was not loaded"
        assert "EXEC /home/user/legacy_auditd ARG1 test_net" in net_trace, "Phase 3 Failed: sandbox did not exec the daemon with test_net"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
