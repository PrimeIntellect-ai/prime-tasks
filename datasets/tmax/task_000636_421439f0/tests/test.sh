#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import secrets
import shutil
import subprocess
import tempfile
import pytest

BARE = "/home/user/git_server/migration.git"
WORKSPACE = "/home/user/migration_workspace"
SOURCE = os.path.join(WORKSPACE, "vnc_parser.cpp")
HOOK = os.path.join(BARE, "hooks/post-receive")
BINARY = "/home/user/build_env/vnc_parser"
RAW_LOG = "/home/user/logs/qemu_raw.log"
OUTPUT_LOG = "/home/user/logs/vnc_endpoints.log"

GIT_ENV = os.environ.copy()
GIT_ENV.update({
    "GIT_CONFIG_COUNT": "1",
    "GIT_CONFIG_KEY_0": "safe.directory",
    "GIT_CONFIG_VALUE_0": "*",
})


def run(cmd, *, input_text=None, cwd=None, timeout=30):
    return subprocess.run(
        cmd,
        input=input_text,
        text=True,
        cwd=cwd,
        env=GIT_ENV,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=True,
    )


def test_vnc_endpoints_log():
    assert os.path.isfile(OUTPUT_LOG), f"Error: {OUTPUT_LOG} does not exist."

    with open(OUTPUT_LOG, "r") as f:
        actual_content = f.read().strip()

    expected_content = (
        "VM_ID: 101 | VNC: 192.168.1.50:5901\n"
        "VM_ID: 102 | VNC: 10.0.0.5:5902\n"
        "VM_ID: 104 | VNC: 127.0.0.1:5900"
    )

    assert actual_content == expected_content, (
        f"Output mismatch in {OUTPUT_LOG}.\n"
        f"Expected:\n{expected_content}\n"
        f"Actual:\n{actual_content}"
    )


def test_hook_permissions():
    assert os.path.isfile(HOOK), f"Error: Hook file {HOOK} does not exist."
    st = os.stat(HOOK)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o700, f"Error: Hook permissions are {oct(perms)}, expected 0o700."


def test_compiled_binary_exists_and_executable():
    assert os.path.isfile(BINARY), f"Error: Compiled binary {BINARY} not found."
    assert os.access(BINARY, os.X_OK), f"Error: Compiled binary {BINARY} is not executable."


def test_git_repositories_and_committed_source_exist():
    assert os.path.isdir(BARE), f"Bare repository {BARE} does not exist."
    assert run(["git", "--git-dir", BARE, "rev-parse", "--is-bare-repository"]).stdout.strip() == "true"

    assert os.path.isdir(os.path.join(WORKSPACE, ".git")), f"Clone {WORKSPACE} does not exist."
    assert run(["git", "-C", WORKSPACE, "rev-parse", "--is-inside-work-tree"]).stdout.strip() == "true"
    assert os.path.isfile(SOURCE), f"Required source file {SOURCE} does not exist."

    committed_source = run(["git", "--git-dir", BARE, "show", "HEAD:vnc_parser.cpp"]).stdout
    with open(SOURCE, "r") as f:
        workspace_source = f.read()
    assert workspace_source == committed_source, "vnc_parser.cpp is not the version committed and pushed to the bare repository."

    status = run(["git", "-C", WORKSPACE, "status", "--porcelain", "--", "vnc_parser.cpp"]).stdout
    assert status.strip() == "", "vnc_parser.cpp is uncommitted or differs from the pushed version."


def test_source_compiles_and_parser_handles_derived_inputs():
    token = secrets.randbelow(800000) + 100000
    cases = [
        (str(token), "172.23.41.9", str(20000 + token % 30000), "qemu-system-x86_64 -m 1536"),
        (str(token + 1), "10.77.8.201", str(30000 + token % 20000), "qemu-system-aarch64 -daemonize -m 768"),
    ]
    parser_input = "".join(
        f'VM_ID={vmid} CMD="{prefix} -vnc {ip}:{port}"\n'
        for vmid, ip, port, prefix in cases
    )
    expected = "".join(
        f"VM_ID: {vmid} | VNC: {ip}:{port}\n"
        for vmid, ip, port, _ in cases
    )

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "vnc_parser")
        run(["g++", SOURCE, "-o", rebuilt], timeout=30)
        result = run([rebuilt], input_text=parser_input)
        assert result.stdout == expected


def test_hook_declares_required_pipeline_and_paths():
    with open(HOOK, "r") as f:
        hook_text = f.read()
    assert "/home/user/build_env" in hook_text
    assert RAW_LOG in hook_text
    assert OUTPUT_LOG in hook_text
    assert "grep" in hook_text, "The hook does not use the required grep filtering stage."
    assert ("awk" in hook_text or "sed" in hook_text), "The hook does not use the required awk/sed prefix-stripping stage."


def test_real_push_triggers_hook_compile_and_dynamic_log_processing():
    nonce = secrets.randbelow(700000) + 200000
    cases = [
        (str(nonce), "192.0.2.17", str(10000 + nonce % 40000), "qemu-system-x86_64 -m 333"),
        (str(nonce + 7), "198.51.100.29", str(10001 + nonce % 40000), "qemu-system-aarch64 -m 777 -daemonize"),
        (str(nonce + 19), "203.0.113.44", str(10002 + nonce % 40000), "qemu-system-x86_64 -monitor stdio"),
    ]
    raw_content = (
        f"[2042-04-03T01:02:03Z] START VM_ID={cases[0][0]} CMD=\"{cases[0][3]} -vnc {cases[0][1]}:{cases[0][2]}\"\n"
        f"[2042-04-03T01:03:03Z] STOP VM_ID={nonce + 1}\n"
        f"[2042-04-03T01:04:03Z] START VM_ID={cases[1][0]} CMD=\"{cases[1][3]} -vnc {cases[1][1]}:{cases[1][2]}\"\n"
        f"[2042-04-03T01:05:03Z] ERROR VM_ID={nonce + 2} FAILED\n"
        f"[2042-04-03T01:06:03Z] START VM_ID={cases[2][0]} CMD=\"{cases[2][3]} -vnc {cases[2][1]}:{cases[2][2]}\"\n"
    )
    expected = "".join(
        f"VM_ID: {vmid} | VNC: {ip}:{port}\n"
        for vmid, ip, port, _ in cases
    )
    parser_input = "".join(
        f'VM_ID={vmid} CMD="{prefix} -vnc {ip}:{port}"\n'
        for vmid, ip, port, prefix in cases
    )

    with open(RAW_LOG, "rb") as f:
        old_raw = f.read()
    old_output = None
    if os.path.exists(OUTPUT_LOG):
        with open(OUTPUT_LOG, "rb") as f:
            old_output = f.read()

    try:
        with open(RAW_LOG, "w") as f:
            f.write(raw_content)

        with tempfile.TemporaryDirectory() as td:
            clone = os.path.join(td, "trigger_clone")
            run(["git", "clone", "--quiet", BARE, clone], timeout=30)
            marker = os.path.join(clone, "verifier_push_marker")
            with open(marker, "w") as f:
                f.write(str(nonce) + "\n")
            run(["git", "-C", clone, "add", "verifier_push_marker"])
            run([
                "git", "-C", clone,
                "-c", "user.name=Verifier",
                "-c", "user.email=verifier@example.invalid",
                "commit", "--quiet", "-m", "Trigger post-receive verification",
            ])
            run(["git", "-C", clone, "push", "--quiet", "origin", "HEAD"], timeout=60)

        assert os.path.isfile(OUTPUT_LOG), "The push did not produce vnc_endpoints.log."
        with open(OUTPUT_LOG, "r") as f:
            actual = f.read()
        assert actual == expected, f"Hook output for derived log data was incorrect.\nExpected:\n{expected}\nActual:\n{actual}"

        assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)
        with open(BINARY, "rb") as f:
            assert f.read(4) == b"\x7fELF", "Hook output vnc_parser is not a compiled executable."
        assert run([BINARY], input_text=parser_input).stdout == expected

        built_source = "/home/user/build_env/vnc_parser.cpp"
        assert os.path.isfile(built_source), "The hook did not check out the latest source into build_env."
        remote_source = run(["git", "--git-dir", BARE, "show", "HEAD:vnc_parser.cpp"]).stdout
        with open(built_source, "r") as f:
            assert f.read() == remote_source
    finally:
        with open(RAW_LOG, "wb") as f:
            f.write(old_raw)
        if old_output is None:
            if os.path.exists(OUTPUT_LOG):
                os.remove(OUTPUT_LOG)
        else:
            with open(OUTPUT_LOG, "wb") as f:
                f.write(old_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
