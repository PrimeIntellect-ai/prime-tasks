#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import ctypes.util
import os
import random
import secrets
import string
import subprocess
import tempfile
import pytest


def test_libsodium_installed():
    """Verify that libsodium was built and installed locally and is usable."""
    prefix = "/home/user/local_libsodium"
    lib_dir = os.path.join(prefix, "lib")
    assert os.path.isdir(lib_dir), f"Local libsodium lib directory not found at {lib_dir}"

    static_lib = os.path.join(lib_dir, "libsodium.a")
    shared_lib = os.path.join(lib_dir, "libsodium.so")
    has_a = os.path.exists(static_lib)
    has_so = os.path.exists(shared_lib)
    assert has_a or has_so, "Neither libsodium.a nor libsodium.so found in /home/user/local_libsodium/lib"

    header = os.path.join(prefix, "include", "sodium.h")
    assert os.path.isfile(header), f"Installed libsodium header not found at {header}"

    source = r'''#include <sodium.h>
int main(void) {
    if (sodium_init() < 0) return 2;
    return crypto_secretbox_keybytes() == 32 ? 0 : 3;
}
'''
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "probe.c")
        obj = os.path.join(td, "probe.o")
        exe = os.path.join(td, "probe")
        with open(src, "w") as f:
            f.write(source)

        compile_proc = subprocess.run(
            ["cc", "-I" + os.path.join(prefix, "include"), "-c", src, "-o", obj],
            capture_output=True,
            text=True,
        )
        assert compile_proc.returncode == 0, (
            "Installed libsodium headers are not compilable:\n" + compile_proc.stderr
        )

        errors = []
        linked = False
        for library in (static_lib, shared_lib):
            if not os.path.exists(library):
                continue
            real_library = os.path.realpath(library)
            assert os.path.isfile(real_library), f"Local library target is not a file: {library}"
            assert os.path.getsize(real_library) > 0, f"Local library is empty: {library}"

            nm_proc = subprocess.run(
                ["nm", "-g", real_library], capture_output=True, text=True
            )
            assert nm_proc.returncode == 0, f"Local library is not a valid library: {library}"
            assert "sodium_init" in nm_proc.stdout, (
                f"Local library does not export sodium_init: {library}"
            )

            link_proc = subprocess.run(
                ["cc", obj, library, "-o", exe], capture_output=True, text=True
            )
            if link_proc.returncode != 0:
                errors.append(f"{library}: {link_proc.stderr}")
                continue

            env = os.environ.copy()
            env["LD_LIBRARY_PATH"] = lib_dir + os.pathsep + env.get("LD_LIBRARY_PATH", "")
            run_proc = subprocess.run([exe], capture_output=True, env=env)
            if run_proc.returncode == 0:
                linked = True
                break
            errors.append(f"{library}: probe exited {run_proc.returncode}")

        assert linked, "No installed local libsodium artifact could be linked and run:\n" + "\n".join(errors)


def test_decryptor_binary_exists():
    """Verify that the agent's decryptor binary and source exist."""
    agent_bin = "/home/user/decryptor"
    agent_src = "/home/user/decryptor.cpp"
    assert os.path.exists(agent_bin), f"Agent binary not found at {agent_bin}"
    assert os.path.isfile(agent_bin), f"{agent_bin} is not a file"
    assert os.access(agent_bin, os.X_OK), f"Agent binary {agent_bin} is not executable"
    assert os.path.isfile(agent_src), f"Agent C++ source not found at {agent_src}"
    assert os.path.getsize(agent_src) > 0, f"Agent C++ source is empty: {agent_src}"
    with open(agent_bin, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{agent_bin} is not a compiled ELF binary"

    oracle_bin = "/app/oracle_bin"
    with open(agent_bin, "rb") as f:
        agent_bytes = f.read()
    with open(oracle_bin, "rb") as f:
        oracle_bytes = f.read()
    assert agent_bytes != oracle_bytes, "Agent binary is byte-identical to the oracle binary"


def _load_sodium():
    name = ctypes.util.find_library("sodium")
    assert name, "System libsodium is unavailable to construct verification cases"
    sodium = ctypes.CDLL(name)
    sodium.sodium_init.restype = ctypes.c_int
    assert sodium.sodium_init() >= 0
    sodium.crypto_secretbox_easy.argtypes = [
        ctypes.POINTER(ctypes.c_ubyte),
        ctypes.POINTER(ctypes.c_ubyte),
        ctypes.c_ulonglong,
        ctypes.POINTER(ctypes.c_ubyte),
        ctypes.POINTER(ctypes.c_ubyte),
    ]
    sodium.crypto_secretbox_easy.restype = ctypes.c_int
    return sodium


def _make_valid_case(sodium, plaintext, prefix, suffix):
    key = bytes(prefix) + suffix.to_bytes(2, "big") + bytes(28)
    nonce = bytes(24)
    message = bytes(plaintext)
    output = (ctypes.c_ubyte * (len(message) + 16))()
    message_buf = (ctypes.c_ubyte * len(message)).from_buffer_copy(message)
    nonce_buf = (ctypes.c_ubyte * len(nonce)).from_buffer_copy(nonce)
    key_buf = (ctypes.c_ubyte * len(key)).from_buffer_copy(key)
    rc = sodium.crypto_secretbox_easy(
        output, message_buf, len(message), nonce_buf, key_buf
    )
    assert rc == 0
    return bytes(output).hex(), bytes(prefix).hex(), message


def test_valid_secretbox_ciphertexts():
    """Exercise successful decryptions with independently constructed ciphertexts."""
    oracle_bin = "/app/oracle_bin"
    agent_bin = "/home/user/decryptor"
    sodium = _load_sodium()

    plaintexts = [
        b"HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello",
        b"HTTP/1.1 404 Not Found\r\n\r\n",
        b"HTTP/1.1 301 Moved Permanently\r\nLocation: /evidence\r\n\r\n",
        b"HTTP/1.1 binary-safe body: evidence-12345",
        b"HTTP/1.1 500 Internal Server Error\r\n\r\nforensic payload",
        b"HTTP/1.1 204 No Content\r\n\r\n",
    ]

    for i, plaintext in enumerate(plaintexts):
        prefix = secrets.token_bytes(2)
        suffix = secrets.randbelow(0x10000)
        ciphertext_hex, prefix_hex, expected = _make_valid_case(
            sodium, plaintext, prefix, suffix
        )
        args = [ciphertext_hex, prefix_hex]

        oracle_proc = subprocess.run([oracle_bin] + args, capture_output=True, timeout=30)
        agent_proc = subprocess.run([agent_bin] + args, capture_output=True, timeout=30)

        assert oracle_proc.returncode == 0, f"Oracle rejected generated valid case {i}"
        assert oracle_proc.stdout == expected, f"Oracle output mismatch on generated case {i}"
        assert oracle_proc.stderr == b"", f"Oracle wrote stderr on generated case {i}"
        assert agent_proc.returncode == 0, f"Agent rejected generated valid case {i}"
        assert agent_proc.stdout == expected, f"Agent plaintext mismatch on generated case {i}"
        assert agent_proc.stderr == b"", f"Agent wrote stderr on generated case {i}"


def generate_hex_string(length):
    return ''.join(random.choices(string.hexdigits.upper(), k=length))


def test_fuzz_equivalence():
    """Fuzz the agent's decryptor against the oracle binary."""
    oracle_bin = "/app/oracle_bin"
    agent_bin = "/home/user/decryptor"

    assert os.path.exists(oracle_bin), f"Oracle binary not found at {oracle_bin}"

    random.seed(42)
    num_iterations = 1000

    for i in range(num_iterations):
        # argv[1] length between 64 and 256, must be even
        len_hex = random.randint(32, 128) * 2
        argv1 = generate_hex_string(len_hex)
        argv2 = generate_hex_string(4)

        args = [argv1, argv2]

        oracle_proc = subprocess.run(
            [oracle_bin] + args,
            capture_output=True,
            text=True
        )

        agent_proc = subprocess.run(
            [agent_bin] + args,
            capture_output=True,
            text=True
        )

        assert oracle_proc.returncode == agent_proc.returncode, (
            f"Return code mismatch on iteration {i}.\n"
            f"Input: {args}\n"
            f"Oracle return code: {oracle_proc.returncode}\n"
            f"Agent return code: {agent_proc.returncode}"
        )

        assert oracle_proc.stdout == agent_proc.stdout, (
            f"Stdout mismatch on iteration {i}.\n"
            f"Input: {args}\n"
            f"Oracle stdout: {repr(oracle_proc.stdout)}\n"
            f"Agent stdout: {repr(agent_proc.stdout)}"
        )

        assert oracle_proc.stderr == agent_proc.stderr, (
            f"Stderr mismatch on iteration {i}.\n"
            f"Input: {args}\n"
            f"Oracle stderr: {repr(oracle_proc.stderr)}\n"
            f"Agent stderr: {repr(agent_proc.stderr)}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
