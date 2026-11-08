#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

import pytest
from elftools.elf.elffile import ELFFile

PRIV_ESC_FILE = "/home/user/priv_escalation.txt"
EXTRACT_SCRIPT = "/home/user/extract_config.py"
EXTRACTED_CONFIG_FILE = "/home/user/extracted_config.txt"
SAFE_RUN_SCRIPT = "/home/user/safe_run.sh"
BINARY = "/home/user/investigation/data_worker"


def section_bytes(path, name):
    with open(path, "rb") as f:
        section = ELFFile(f).get_section_by_name(name)
        assert section is not None, f"ELF section {name} is missing"
        return section.data()


def test_priv_escalation_identification():
    assert os.path.isfile(PRIV_ESC_FILE), f"The file {PRIV_ESC_FILE} does not exist."
    with open(PRIV_ESC_FILE, "r") as f:
        content = f.read().strip()

    expected_line = "ExecStartPre=+/bin/chmod +s /home/user/investigation/data_worker"
    assert content == expected_line, f"The content of {PRIV_ESC_FILE} is incorrect. Expected the exact ExecStartPre line."


def test_extracted_config():
    assert os.path.isfile(EXTRACTED_CONFIG_FILE), f"The file {EXTRACTED_CONFIG_FILE} does not exist."
    with open(EXTRACTED_CONFIG_FILE, "r") as f:
        content = f.read().strip()

    expected_ip = "198.51.100.45:1337"
    assert content == expected_ip, f"The content of {EXTRACTED_CONFIG_FILE} is incorrect. Expected the extracted IP and port."
    assert content.encode("ascii") == section_bytes(BINARY, ".mal_cfg"), "The extracted output does not match the ELF section."


def test_extractor_exists_and_actually_parses_elf():
    assert os.path.isfile(EXTRACT_SCRIPT), f"The script {EXTRACT_SCRIPT} does not exist."

    token = ("203.0.113." + str(int.from_bytes(os.urandom(1), "big") % 250 + 1) + ":" + str(int.from_bytes(os.urandom(2), "big") % 50000 + 1024)).encode("ascii")
    binary_backup = BINARY + ".verifier-backup-" + uuid.uuid4().hex
    old_output = Path(EXTRACTED_CONFIG_FILE).read_bytes() if os.path.exists(EXTRACTED_CONFIG_FILE) else None

    with tempfile.TemporaryDirectory() as td:
        source = os.path.join(td, "fixture.c")
        fixture = os.path.join(td, "fixture")
        payload = os.path.join(td, "payload.bin")
        Path(source).write_text("int main(void) { return 0; }\n")
        Path(payload).write_bytes(token)
        subprocess.run(["gcc", source, "-o", fixture], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        subprocess.run(["objcopy", "--add-section", f".mal_cfg={payload}", fixture], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        os.replace(BINARY, binary_backup)
        try:
            subprocess.run(["cp", "--preserve=mode", fixture, BINARY], check=True)
            if os.path.lexists(EXTRACTED_CONFIG_FILE):
                os.unlink(EXTRACTED_CONFIG_FILE)
            result = subprocess.run(["python3", EXTRACT_SCRIPT], cwd="/", stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
            assert result.returncode == 0, f"Extractor failed: {result.stderr.decode(errors='replace')}"
            assert os.path.isfile(EXTRACTED_CONFIG_FILE), "Extractor did not create extracted_config.txt."
            assert Path(EXTRACTED_CONFIG_FILE).read_bytes() == token, "Extractor did not decode the randomized .mal_cfg section."
        finally:
            if os.path.lexists(BINARY):
                os.unlink(BINARY)
            os.replace(binary_backup, BINARY)
            if old_output is None:
                if os.path.lexists(EXTRACTED_CONFIG_FILE):
                    os.unlink(EXTRACTED_CONFIG_FILE)
            else:
                Path(EXTRACTED_CONFIG_FILE).write_bytes(old_output)


def test_safe_run_script_exists_and_executable():
    assert os.path.isfile(SAFE_RUN_SCRIPT), f"The script {SAFE_RUN_SCRIPT} does not exist."
    assert os.access(SAFE_RUN_SCRIPT, os.X_OK), f"The script {SAFE_RUN_SCRIPT} is not executable."


def test_safe_run_script_content():
    with open(SAFE_RUN_SCRIPT, "r") as f:
        content = f.read()

    assert "bwrap" in content, "The script does not use bwrap (Bubblewrap)."
    assert re.search(r"--ro-bind\s+/usr\s+/usr", content), "Missing --ro-bind for /usr."
    assert re.search(r"--ro-bind\s+/lib\s+/lib", content), "Missing --ro-bind for /lib."
    assert re.search(r"--ro-bind\s+/home/user/investigation\s+/home/user/investigation", content), "Missing --ro-bind for /home/user/investigation."
    assert re.search(r"--tmpfs\s+/tmp", content), "Missing --tmpfs for /tmp."

    has_unshare_all = "--unshare-all" in content
    has_individual_unshares = all(flag in content for flag in [
        "--unshare-user", "--unshare-ipc", "--unshare-pid", "--unshare-net", "--unshare-uts"
    ])
    assert has_unshare_all or has_individual_unshares, "The script does not unshare all required namespaces."

    binary_path = "/home/user/investigation/data_worker"
    assert binary_path in content, f"The script does not execute {binary_path}."
    bwrap_index = content.find("bwrap")
    binary_index = content.find(binary_path, bwrap_index)
    assert binary_index > bwrap_index, "The binary is not passed as an argument to bwrap."


def captured_bwrap_arguments():
    real = "/usr/bin/bwrap"
    backup = real + ".verifier-backup-" + uuid.uuid4().hex
    capture = "/tmp/bwrap-args-" + uuid.uuid4().hex
    os.replace(real, backup)
    try:
        Path(real).write_text("#!/bin/sh\nprintf '%s\\0' \"$@\" > " + capture + "\n")
        os.chmod(real, 0o755)
        result = subprocess.run([SAFE_RUN_SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        assert result.returncode == 0, f"safe_run.sh failed while its bwrap invocation was inspected: {result.stderr.decode(errors='replace')}"
        assert os.path.isfile(capture), "safe_run.sh did not invoke the installed bwrap executable."
        raw = Path(capture).read_bytes()
        return [part.decode() for part in raw.split(b"\0") if part]
    finally:
        if os.path.lexists(real):
            os.unlink(real)
        os.replace(backup, real)
        if os.path.exists(capture):
            os.unlink(capture)


def has_triplet(args, option, source, destination):
    return any(args[i:i + 3] == [option, source, destination] for i in range(len(args) - 2))


def has_pair(args, option, value):
    return any(args[i:i + 2] == [option, value] for i in range(len(args) - 1))


def test_safe_run_real_bwrap_arguments():
    args = captured_bwrap_arguments()
    assert has_triplet(args, "--ro-bind", "/usr", "/usr")
    assert has_triplet(args, "--ro-bind", "/lib", "/lib")
    assert has_triplet(args, "--ro-bind", "/home/user/investigation", "/home/user/investigation")
    if os.path.exists("/lib64"):
        assert has_triplet(args, "--ro-bind", "/lib64", "/lib64"), "Existing /lib64 is not read-only bound."
    assert has_pair(args, "--tmpfs", "/tmp")
    assert not any(len(args[i:i + 3]) == 3 and args[i] in ("--bind", "--ro-bind") and args[i + 1] == "/tmp" for i in range(len(args) - 2)), "Host /tmp is bind-mounted into the sandbox."

    required = {"--unshare-user", "--unshare-pid", "--unshare-ipc", "--unshare-net", "--unshare-uts"}
    assert "--unshare-all" in args or required.issubset(set(args)), "Required namespaces are not unshared in the actual bwrap arguments."
    assert has_pair(args, "--cap-drop", "ALL"), "The actual bwrap invocation does not drop all capabilities."
    assert args and args[-1] == BINARY, "data_worker is not the command executed by bwrap."


def test_safe_run_enforces_isolation_and_capability_drop():
    nonce = uuid.uuid4().hex
    probe_source = r'''
#include <errno.h>
#include <fcntl.h>
#include <linux/capability.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

static int can_create(const char *p) {
    int fd = open(p, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (fd >= 0) { close(fd); unlink(p); return 1; }
    return 0;
}

int main(void) {
    struct __user_cap_header_struct h;
    struct __user_cap_data_struct d[2];
    memset(&h, 0, sizeof(h)); memset(d, 0, sizeof(d));
    h.version = _LINUX_CAPABILITY_VERSION_3;
    h.pid = 0;

    if (access("/tmp/input.dat", F_OK) == 0) return 20;
    int in = open("/tmp/input.dat", O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (in < 0 || write(in, "sandbox-data", 12) != 12) return 21;
    close(in);
    int out = open("/tmp/output.dat", O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (out < 0 || write(out, "sandbox-data", 12) != 12) return 22;
    close(out);

    if (can_create("/usr/.verifier-@NONCE@")) return 23;
    if (can_create("/lib/.verifier-@NONCE@")) return 24;
    if (can_create("/home/user/investigation/.verifier-@NONCE@")) return 25;
    if (syscall(SYS_capget, &h, d) != 0) return 26;
    if (d[0].effective || d[0].permitted || d[0].inheritable ||
        d[1].effective || d[1].permitted || d[1].inheritable) return 27;
    sleep(5);
    return 0;
}
'''.replace("@NONCE@", nonce)

    binary_backup = BINARY + ".verifier-backup-" + uuid.uuid4().hex
    host_input = "/tmp/input.dat"
    host_input_backup = host_input + ".verifier-backup-" + uuid.uuid4().hex
    had_host_input = os.path.lexists(host_input)
    if had_host_input:
        os.replace(host_input, host_input_backup)

    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "probe.c")
        probe = os.path.join(td, "probe")
        Path(src).write_text(probe_source)
        subprocess.run(["gcc", "-O2", src, "-o", probe], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        os.replace(BINARY, binary_backup)
        try:
            subprocess.run(["cp", "--preserve=mode", probe, BINARY], check=True)
            Path(host_input).write_text("HOST-TMP-MUST-NOT-BE-VISIBLE-" + nonce)
            probe_stat = os.stat(BINARY)
            parent_ns = {name: os.readlink(f"/proc/self/ns/{name}") for name in ("user", "pid", "ipc", "net", "uts")}

            process = subprocess.Popen([SAFE_RUN_SCRIPT], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            sandbox_pid = None
            deadline = time.time() + 8
            while time.time() < deadline and process.poll() is None:
                for entry in os.listdir("/proc"):
                    if not entry.isdigit():
                        continue
                    try:
                        current = os.stat(f"/proc/{entry}/exe")
                        if (current.st_dev, current.st_ino) == (probe_stat.st_dev, probe_stat.st_ino):
                            sandbox_pid = int(entry)
                            break
                    except (FileNotFoundError, PermissionError, ProcessLookupError):
                        pass
                if sandbox_pid is not None:
                    break
                time.sleep(0.05)

            assert sandbox_pid is not None, "The probe was not executed inside the sandbox."
            child_ns = {name: os.readlink(f"/proc/{sandbox_pid}/ns/{name}") for name in parent_ns}
            for name in parent_ns:
                assert child_ns[name] != parent_ns[name], f"The {name} namespace was not unshared."

            stdout, stderr = process.communicate(timeout=12)
            assert process.returncode == 0, f"Sandbox probe failed with status {process.returncode}: {stderr.decode(errors='replace')}"
            assert Path(host_input).read_text() == "HOST-TMP-MUST-NOT-BE-VISIBLE-" + nonce, "The sandbox used or modified the host's /tmp/input.dat."
            assert not os.path.exists("/tmp/output.dat") or os.path.getmtime("/tmp/output.dat") < os.path.getmtime(host_input), "Sandbox output escaped into the host /tmp."
        finally:
            if os.path.lexists(BINARY):
                os.unlink(BINARY)
            os.replace(binary_backup, BINARY)
            if os.path.lexists(host_input):
                os.unlink(host_input)
            if had_host_input:
                os.replace(host_input_backup, host_input)
            for path in (f"/usr/.verifier-{nonce}", f"/lib/.verifier-{nonce}", f"/home/user/investigation/.verifier-{nonce}"):
                if os.path.lexists(path):
                    os.unlink(path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
