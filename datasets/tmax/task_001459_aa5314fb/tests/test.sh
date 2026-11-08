#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pwd
import secrets
import shutil
import stat
import subprocess
import tempfile

CONFIG_PATH = "/home/user/edge_config.txt"
SOURCE_PATH = "/home/user/build_edge_node.rs"
BINARY_PATH = "/home/user/build_edge_node"
SCRIPT_PATH = "/home/user/run_vm.sh"


def test_edge_config_exists():
    assert os.path.isfile(CONFIG_PATH), f"{CONFIG_PATH} does not exist."
    with open(CONFIG_PATH, "r") as f:
        content = f.read()
    assert "MAC=52:54:00:11:22:33" in content, "MAC address not found in edge_config.txt"
    assert "VNC_DISPLAY=4" in content, "VNC_DISPLAY not found in edge_config.txt"
    assert "GUEST_PORT=80" in content, "GUEST_PORT not found in edge_config.txt"
    assert "HOST_PORT=8080" in content, "HOST_PORT not found in edge_config.txt"


def test_rust_source_exists():
    assert os.path.isfile(SOURCE_PATH), f"{SOURCE_PATH} does not exist."


def test_rust_binary_exists_and_executable():
    assert os.path.isfile(BINARY_PATH), f"{BINARY_PATH} does not exist."
    assert os.access(BINARY_PATH, os.X_OK), f"{BINARY_PATH} is not executable."


def test_run_vm_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable."


def test_run_vm_script_content():
    try:
        user_uid = pwd.getpwnam("user").pw_uid
    except KeyError:
        assert False, "User 'user' does not exist in the system."

    expected_cmd = (
        f"qemu-system-x86_64 -m 256 -vnc 127.0.0.1:4 "
        f"-netdev user,id=net0,hostfwd=tcp::8080-:80 "
        f"-device virtio-net-pci,netdev=net0,mac=52:54:00:11:22:33 "
        f"-fw_cfg name=opt/edge_uid,string={user_uid}"
    )

    with open(SCRIPT_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip() and not line.strip().startswith("#")]

    assert len(lines) == 1, "run_vm.sh should contain exactly one line of command (excluding comments and empty lines)."
    actual_cmd = lines[0]
    assert actual_cmd == expected_cmd, f"run_vm.sh content mismatch.\nExpected: {expected_cmd}\nGot: {actual_cmd}"


def _snapshot(path):
    st = os.stat(path)
    with open(path, "rb") as f:
        data = f.read()
    return data, stat.S_IMODE(st.st_mode), st.st_uid, st.st_gid


def _restore(path, snapshot):
    data, mode, uid, gid = snapshot
    if os.path.lexists(path):
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)
    with open(path, "wb") as f:
        f.write(data)
    os.chmod(path, mode)
    os.chown(path, uid, gid)


def _passwd_with_uid(original, new_uid):
    text = original.decode("utf-8")
    output = []
    found = False
    for line in text.splitlines(keepends=True):
        body = line[:-1] if line.endswith("\n") else line
        fields = body.split(":")
        if fields and fields[0] == "user":
            assert len(fields) >= 7, "Malformed user entry in /etc/passwd"
            fields[2] = str(new_uid)
            body = ":".join(fields)
            found = True
        output.append(body + ("\n" if line.endswith("\n") else ""))
    assert found, "User 'user' does not exist in /etc/passwd"
    return "".join(output).encode("utf-8")


def _demote_to_user(uid, gid):
    def demote():
        os.initgroups("user", gid)
        os.setgid(gid)
        os.setuid(uid)
    return demote


def _exercise(binary, account, original_passwd, mac, vnc, guest, host, test_uid):
    config = (
        f"MAC={mac}\n"
        f"VNC_DISPLAY={vnc}\n"
        f"GUEST_PORT={guest}\n"
        f"HOST_PORT={host}\n"
    )
    with open(CONFIG_PATH, "w") as f:
        f.write(config)
    os.chmod(CONFIG_PATH, 0o644)

    with open("/etc/passwd", "wb") as f:
        f.write(_passwd_with_uid(original_passwd, test_uid))

    if os.path.lexists(SCRIPT_PATH):
        os.unlink(SCRIPT_PATH)

    result = subprocess.run(
        [binary],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
        preexec_fn=_demote_to_user(account.pw_uid, account.pw_gid),
        env={"HOME": "/home/user", "PATH": "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"},
    )
    assert result.returncode == 0, (
        f"{binary} failed for a dynamically generated configuration.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.isfile(SCRIPT_PATH), f"{binary} did not generate {SCRIPT_PATH}"
    mode = stat.S_IMODE(os.stat(SCRIPT_PATH).st_mode)
    assert mode & 0o111, f"{binary} did not make {SCRIPT_PATH} executable"

    expected = (
        f"qemu-system-x86_64 -m 256 -vnc 127.0.0.1:{vnc} "
        f"-netdev user,id=net0,hostfwd=tcp::{host}-:{guest} "
        f"-device virtio-net-pci,netdev=net0,mac={mac} "
        f"-fw_cfg name=opt/edge_uid,string={test_uid}"
    )
    with open(SCRIPT_PATH, "r") as f:
        generated = f.read()
    assert generated.splitlines() == [expected], (
        f"{binary} did not use the dynamic configuration and passwd values.\n"
        f"Expected: {expected}\nGot: {generated!r}"
    )


def test_program_and_source_are_dynamic():
    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "build_edge_node must be a compiled executable binary"

    account = pwd.getpwnam("user")
    passwd_snapshot = _snapshot("/etc/passwd")
    config_snapshot = _snapshot(CONFIG_PATH)
    script_snapshot = _snapshot(SCRIPT_PATH)
    original_passwd = passwd_snapshot[0]

    with tempfile.TemporaryDirectory(prefix="edge_verify_") as tempdir:
        rebuilt = os.path.join(tempdir, "build_edge_node_from_source")
        try:
            compile_result = subprocess.run(
                ["rustc", SOURCE_PATH, "-o", rebuilt],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            assert compile_result.returncode == 0, (
                "build_edge_node.rs does not compile with rustc.\n"
                f"stdout: {compile_result.stdout}\nstderr: {compile_result.stderr}"
            )

            used_uids = {entry.pw_uid for entry in pwd.getpwall()}
            for round_number in range(2):
                while True:
                    test_uid = 20000 + secrets.randbelow(30000)
                    if test_uid not in used_uids:
                        used_uids.add(test_uid)
                        break
                mac = "52:54:%02X:%02X:%02X:%02X" % tuple(secrets.randbelow(256) for _ in range(4))
                vnc = 10 + secrets.randbelow(80)
                guest = 1024 + secrets.randbelow(20000)
                host = 30000 + secrets.randbelow(20000)

                for executable in (BINARY_PATH, rebuilt):
                    with open("/etc/passwd", "wb") as f:
                        f.write(original_passwd)
                    _exercise(executable, account, original_passwd, mac, vnc, guest, host, test_uid)
        finally:
            _restore("/etc/passwd", passwd_snapshot)
            _restore(CONFIG_PATH, config_snapshot)
            _restore(SCRIPT_PATH, script_snapshot)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
