#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import shutil
import struct
import subprocess
import tempfile

FILTER_SCRIPT = "/home/user/token_filter.py"
SANDBOX_SCRIPT = "/home/user/sandbox_test.sh"
LEGACY_SERVICE = "/app/legacy_auth_service"
CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"


def run_filter(token):
    result = subprocess.run(
        ["python3", FILTER_SCRIPT, token],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=5,
    )
    assert result.returncode == 0, f"Filter failed for {token}: {result.stdout}"
    return result.stdout.strip()


def test_sandbox_script_exists_and_valid():
    assert os.path.exists(SANDBOX_SCRIPT), f"Missing sandbox script at {SANDBOX_SCRIPT}"
    assert os.access(SANDBOX_SCRIPT, os.X_OK), f"Sandbox script {SANDBOX_SCRIPT} is not executable"

    with open(SANDBOX_SCRIPT, "r") as f:
        content = f.read()

    assert "bwrap" in content, "Sandbox script must use bwrap"
    assert "--unshare-all" in content, "Sandbox script must isolate network with --unshare-all"
    assert "--ro-bind" in content, "Sandbox script must mount directories read-only"


def test_sandbox_executes_service_with_isolation():
    with open(sorted(glob.glob(os.path.join(CLEAN_DIR, "*.txt")))[0]) as f:
        ordinary_token = f.read().strip()

    real_run = subprocess.run(
        [SANDBOX_SCRIPT, ordinary_token],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert real_run.returncode == 0, f"Sandbox could not execute the legacy service: {real_run.stderr}"

    marker = "PROBE_" + secrets.token_hex(16)
    probe_token = secrets.token_hex(16)
    probe_path = "/tmp/" + marker.lower()
    source = r'''
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

int main(int argc, char **argv) {
    int fd, net = 0, root_group = 0;
    gid_t groups[128];
    int n = getgroups(128, groups);
    for (int i = 0; i < n; i++) if (groups[i] == 0) root_group = 1;

    struct ifaddrs *list = NULL;
    if (getifaddrs(&list) == 0) {
        for (struct ifaddrs *p = list; p; p = p->ifa_next) {
            if (!p->ifa_addr || !p->ifa_name || strcmp(p->ifa_name, "lo") == 0) continue;
            if (p->ifa_addr->sa_family == AF_INET || p->ifa_addr->sa_family == AF_INET6) net++;
        }
        freeifaddrs(list);
    }

    errno = 0;
    fd = open("__PROBE_PATH__", O_WRONLY | O_CREAT | O_EXCL, 0600);
    int write_succeeded = (fd >= 0);
    if (fd >= 0) {
        close(fd);
        unlink("__PROBE_PATH__");
    }

    int arg_ok = argc == 2 && strcmp(argv[1], "__TOKEN__") == 0;
    printf("__MARKER__ UID=%ld EUID=%ld WRITE=%d NET=%d ARG=%d ROOTGROUP=%d\n",
           (long)getuid(), (long)geteuid(), write_succeeded, net, arg_ok, root_group);
    return 0;
}
'''.replace("__PROBE_PATH__", probe_path).replace("__TOKEN__", probe_token).replace("__MARKER__", marker)

    os.chmod("/tmp", 0o1777)
    try:
        os.unlink(probe_path)
    except FileNotFoundError:
        pass

    with tempfile.TemporaryDirectory(prefix="sandbox-verifier-") as td:
        src = os.path.join(td, "probe.c")
        probe = os.path.join(td, "probe")
        backup = os.path.join(td, "legacy_auth_service.backup")
        with open(src, "w") as f:
            f.write(source)
        subprocess.run(["gcc", src, "-o", probe], check=True, timeout=20)
        shutil.copy2(LEGACY_SERVICE, backup)
        try:
            shutil.copy2(probe, LEGACY_SERVICE)
            os.chmod(LEGACY_SERVICE, 0o755)
            result = subprocess.run(
                [SANDBOX_SCRIPT, probe_token],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
        finally:
            shutil.copy2(backup, LEGACY_SERVICE)
            os.chmod(LEGACY_SERVICE, 0o755)

    assert result.returncode == 0, f"Sandboxed probe failed: {result.stderr}"
    lines = [line.strip() for line in result.stdout.splitlines() if line.startswith(marker + " ")]
    assert len(lines) == 1, "Sandbox script did not actually execute the service binary"
    fields = dict(item.split("=", 1) for item in lines[0].split()[1:])
    assert fields["ARG"] == "1", "Sandbox did not pass the token argument to the service"
    assert fields["UID"] != "0" and fields["EUID"] != "0", "Sandbox did not drop root privileges"
    assert fields["ROOTGROUP"] == "0", "Sandbox retained the root supplementary group"
    assert fields["WRITE"] == "0", "Sandbox root filesystem was writable"
    assert fields["NET"] == "0", "Sandbox retained access to a non-loopback network interface"


def test_token_filter_exists():
    assert os.path.exists(FILTER_SCRIPT), f"Missing token filter script at {FILTER_SCRIPT}"


def test_token_filter_correctness():
    clean_files = glob.glob(os.path.join(CLEAN_DIR, "*.txt"))
    evil_files = glob.glob(os.path.join(EVIL_DIR, "*.txt"))

    assert len(clean_files) > 0, "No clean files found"
    assert len(evil_files) > 0, "No evil files found"

    clean_bypassed = []
    evil_bypassed = []

    for fpath in clean_files:
        with open(fpath, "r") as f:
            token = f.read().strip()
        try:
            output = subprocess.check_output(
                ["python3", FILTER_SCRIPT, token],
                text=True,
                stderr=subprocess.STDOUT
            ).strip()
            if output != "CLEAN":
                clean_bypassed.append(os.path.basename(fpath))
        except subprocess.CalledProcessError:
            clean_bypassed.append(os.path.basename(fpath))

    for fpath in evil_files:
        with open(fpath, "r") as f:
            token = f.read().strip()
        try:
            output = subprocess.check_output(
                ["python3", FILTER_SCRIPT, token],
                text=True,
                stderr=subprocess.STDOUT
            ).strip()
            if output != "EVIL":
                evil_bypassed.append(os.path.basename(fpath))
        except subprocess.CalledProcessError:
            evil_bypassed.append(os.path.basename(fpath))

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_bypassed:
        error_msgs.append(f"{len(clean_bypassed)} of {len(clean_files)} clean modified: {', '.join(clean_bypassed)}")

    assert not error_msgs, " | ".join(error_msgs)


def test_token_filter_hidden_randomized_tokens():
    differential = 0xDEADBEEF
    for _ in range(100):
        first = secrets.randbits(32)
        second = first ^ differential
        evil = struct.pack(">II", first, second) + secrets.token_bytes(8)
        assert run_filter(evil.hex()) == "EVIL"

    for _ in range(100):
        while True:
            clean = secrets.token_bytes(16)
            first, second = struct.unpack(">II", clean[:8])
            if (first ^ second) != differential:
                break
        assert run_filter(clean.hex()) == "CLEAN"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
