#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import glob
import os
import random
import signal
import shutil
import subprocess
import tempfile


def generate_payload(syscalls: str, xor_key: int = 0x5A) -> bytes:
    encrypted = bytes([ord(c) ^ xor_key for c in syscalls])
    return base64.b64encode(encrypted)


def create_test_binary(temp_dir: str, name: str, payload=None):
    source_path = os.path.join(temp_dir, name + ".S")
    base_bin = os.path.join(temp_dir, name + "_base")
    final_bin = os.path.join(temp_dir, name)
    source = r'''
.section .rodata
newline: .ascii "\n"
badenv:  .ascii "BADENV\n"
.section .text
.global _start
_start:
    movq (%rsp), %rbx
    cmpq $2, %rbx
    jb finish
    movq 16(%rsp), %rsi
    xorq %rdx, %rdx
length_loop:
    cmpb $0, (%rsi,%rdx,1)
    je write_arg
    incq %rdx
    jmp length_loop
write_arg:
    movq $1, %rax
    movq $1, %rdi
    syscall
    movq $1, %rax
    movq $1, %rdi
    leaq newline(%rip), %rsi
    movq $1, %rdx
    syscall
    leaq 16(%rsp,%rbx,8), %rax
    cmpq $0, (%rax)
    je finish
    movq $1, %rax
    movq $1, %rdi
    leaq badenv(%rip), %rsi
    movq $7, %rdx
    syscall
finish:
    movq $231, %rax
    xorq %rdi, %rdi
    syscall
'''
    with open(source_path, "w") as f:
        f.write(source)
    subprocess.run(["gcc", "-nostdlib", "-static", source_path, "-o", base_bin], check=True)
    if payload is None:
        shutil.copy2(base_bin, final_bin)
    else:
        payload_path = os.path.join(temp_dir, name + "_payload.bin")
        with open(payload_path, "wb") as f:
            f.write(payload)
        subprocess.run(
            ["objcopy", "--add-section", ".secpolicy=" + payload_path, base_bin, final_bin],
            check=True,
        )
    return final_bin


def assert_installed_libseccomp():
    source_dir = "/app/vendored/libseccomp-2.5.4"
    prefix = "/app/libs"
    assert os.path.isdir(source_dir), "Vendored libseccomp source is missing"
    assert os.path.isfile(os.path.join(source_dir, "configure")), "configure is missing"

    candidates = [os.path.join(source_dir, "configure")]
    candidates.extend(glob.glob(os.path.join(source_dir, "Makefile*")))
    for path in candidates:
        if os.path.isfile(path):
            with open(path, "rb") as f:
                assert b"-mwrong-arch" not in f.read(), f"Invalid compiler flag remains in {path}"

    header = os.path.join(prefix, "include", "seccomp.h")
    libraries = [p for p in glob.glob(os.path.join(prefix, "lib", "libseccomp.so*")) if os.path.isfile(p)]
    libraries += [p for p in glob.glob(os.path.join(prefix, "lib", "libseccomp.a")) if os.path.isfile(p)]
    assert os.path.isfile(header) and os.path.getsize(header) > 0, "libseccomp header was not installed"
    assert libraries and any(os.path.getsize(p) > 0 for p in libraries), "libseccomp library was not installed"

    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "smoke.c")
        exe = os.path.join(td, "smoke")
        with open(src, "w") as f:
            f.write("#include <seccomp.h>\nint main(void){scmp_filter_ctx c=seccomp_init(SCMP_ACT_ALLOW); if(!c)return 1; seccomp_release(c); return 0;}\n")
        subprocess.run([
            "gcc", src, "-I/app/libs/include", "-L/app/libs/lib",
            "-Wl,-rpath,/app/libs/lib", "-lseccomp", "-o", exe
        ], check=True)
        subprocess.run([exe], check=True, env={"LD_LIBRARY_PATH": "/app/libs/lib"})


def test_secure_runner_equivalence():
    assert_installed_libseccomp()

    agent_source = "/home/user/secure_runner.cpp"
    agent_bin = "/home/user/secure_runner"
    assert os.path.isfile(agent_source), f"Agent source not found at {agent_source}"
    assert os.path.isfile(agent_bin), f"Agent binary not found at {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent binary {agent_bin} is not executable"
    with open(agent_bin, "rb") as f:
        assert f.read(4) == b"\x7fELF", "secure_runner is not an ELF executable"

    with tempfile.TemporaryDirectory() as build_dir:
        rebuilt = os.path.join(build_dir, "secure_runner_rebuilt")
        subprocess.run([
            "g++", "-O2", agent_source, "-I/app/libs/include", "-L/app/libs/lib",
            "-Wl,-rpath,/app/libs/lib", "-lelf", "-lseccomp", "-o", rebuilt
        ], check=True)

        valid_syscalls = "execve,write,exit_group"
        missing_write_syscalls = "execve,exit_group"

        valid = create_test_binary(build_dir, "bin_valid", generate_payload(valid_syscalls))
        missing_write = create_test_binary(
            build_dir, "bin_missing_write", generate_payload(missing_write_syscalls)
        )
        bad_xor = create_test_binary(
            build_dir, "bin_bad_xor", generate_payload(valid_syscalls, xor_key=0x11)
        )
        bad_b64 = create_test_binary(build_dir, "bin_bad_b64", b"NOT_BASE64_!@#")
        missing_policy = create_test_binary(build_dir, "bin_missing_secpolicy", None)

        expected = {
            valid: lambda arg: (0, (arg + "\n").encode()),
            missing_write: lambda arg: (-signal.SIGSYS, b""),
            bad_xor: lambda arg: (-signal.SIGSYS, b""),
            bad_b64: lambda arg: (-signal.SIGSYS, b""),
            missing_policy: lambda arg: (255, b""),
        }

        random.seed(42)
        for runner in (agent_bin, rebuilt):
            assert subprocess.run([runner], capture_output=True).returncode == 255
            assert subprocess.run([runner, valid, "x", "extra"], capture_output=True).returncode == 255

            binaries = list(expected)
            for i in range(100):
                test_bin = random.choice(binaries)
                arg = "".join(random.choices(
                    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
                    k=random.randint(1, 64),
                ))
                expected_code, expected_stdout = expected[test_bin](arg)
                result = subprocess.run([runner, test_bin, arg], capture_output=True)
                assert result.returncode == expected_code, (
                    f"Mismatch on iteration {i} for {os.path.basename(test_bin)}: "
                    f"expected exit {expected_code}, got {result.returncode}; "
                    f"stdout={result.stdout!r}, stderr={result.stderr!r}"
                )
                assert result.stdout == expected_stdout, (
                    f"Mismatch on iteration {i} for {os.path.basename(test_bin)}: "
                    f"expected stdout {expected_stdout!r}, got {result.stdout!r}"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
