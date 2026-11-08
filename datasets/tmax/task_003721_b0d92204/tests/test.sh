#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import random
import string
import subprocess
import tempfile


def generate_fuzz_inputs(n=100, seed=42):
    random.seed(seed)
    inputs = []
    for _ in range(n):
        username_len = random.randint(3, 10)
        username = ''.join(random.choices(string.ascii_lowercase, k=username_len))
        fingerprint_chars = string.ascii_letters + string.digits + "+/"
        fingerprint = ''.join(random.choices(fingerprint_chars, k=43))
        has_sudo = random.choice(['0', '1'])
        inputs.append(f"{username},SHA256:{fingerprint},{has_sudo}\n")
    return inputs


def expected_output(inp):
    line = inp.rstrip("\n")
    username, _fingerprint, has_sudo = line.split(",")
    audit = f"AUDIT_TOKEN:user={username}:sudo={has_sudo}".encode("utf-8")
    return base64.b64encode(audit) + b"\n"


def test_libb64_compiled():
    lib_root = "/app/libb64-1.2.1"
    lib_path = f"{lib_root}/src/libb64.a"

    # The repaired Makefile must actually be usable, not merely accompanied by
    # an arbitrary file named libb64.a.
    build = subprocess.run(
        ["make", "-C", lib_root],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert build.returncode == 0, (
        "The vendored libb64 build failed. Did you repair src/Makefile?\n"
        + build.stderr.decode("utf-8", "replace")
    )
    assert os.path.isfile(lib_path), f"Expected static library {lib_path} does not exist. Did you fix the Makefile and run make?"

    members = subprocess.run(
        ["ar", "t", lib_path],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    ).stdout.decode("utf-8", "replace")
    assert "cencode.o" in members, "libb64.a does not contain the Base64 encoder object"

    probe_source = r'''#include <stdio.h>
#include <string.h>
#include <b64/cencode.h>
int main(void) {
    base64_encodestate state;
    char out[32];
    int n;
    base64_init_encodestate(&state);
    n = base64_encode_block("abc", 3, out, &state);
    n += base64_encode_blockend(out + n, &state);
    return fwrite(out, 1, n, stdout) == (size_t)n ? 0 : 1;
}
'''
    with tempfile.TemporaryDirectory() as td:
        src = os.path.join(td, "probe.c")
        exe = os.path.join(td, "probe")
        with open(src, "w", encoding="utf-8") as f:
            f.write(probe_source)
        compile_proc = subprocess.run(
            ["gcc", "-I/app/libb64-1.2.1/include", src, lib_path, "-o", exe],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert compile_proc.returncode == 0, "libb64.a could not link a real encoder program: " + compile_proc.stderr.decode("utf-8", "replace")
        probe = subprocess.run([exe], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
        assert probe.returncode == 0
        assert probe.stdout == b"YWJj\n", f"libb64 encoder returned unexpected output: {probe.stdout!r}"


def test_agent_executable_exists():
    agent_path = "/home/user/audit_token_gen"
    source_path = "/home/user/audit_token_gen.c"
    assert os.path.isfile(source_path), f"Expected C source {source_path} does not exist."
    assert os.path.isfile(agent_path), f"Agent executable {agent_path} does not exist."
    assert os.access(agent_path, os.X_OK), f"Agent {agent_path} is not executable."

    source = open(source_path, encoding="utf-8", errors="replace").read()
    assert "<b64/cencode.h>" in source
    for api in ("base64_init_encodestate", "base64_encode_block", "base64_encode_blockend"):
        assert api in source, f"The generator source does not use required libb64 API {api}"

    # Rebuild the submitted source against the repaired vendored archive so the
    # tested implementation cannot be an unrelated prebuilt executable.
    rebuilt = "/tmp/audit_token_gen_rebuilt"
    compile_proc = subprocess.run(
        [
            "gcc",
            "-I/app/libb64-1.2.1/include",
            source_path,
            "/app/libb64-1.2.1/src/libb64.a",
            "-o",
            rebuilt,
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_proc.returncode == 0, "Submitted C source does not compile and link against libb64.a: " + compile_proc.stderr.decode("utf-8", "replace")


def test_fuzz_equivalence():
    agent_paths = ["/home/user/audit_token_gen", "/tmp/audit_token_gen_rebuilt"]
    inputs = generate_fuzz_inputs(100, seed=12345)

    for agent_path in agent_paths:
        assert os.path.isfile(agent_path), f"Agent {agent_path} missing."
        for i, inp in enumerate(inputs):
            proc_agent = subprocess.run(
                [agent_path],
                input=inp.encode("utf-8"),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            expected = expected_output(inp)
            assert proc_agent.returncode == 0, f"Nonzero return code on input {i}: {inp!r}"
            assert proc_agent.stdout == expected, (
                f"Stdout mismatch on input {i}: {inp!r}.\n"
                f"Expected stdout: {expected!r}\nAgent stdout: {proc_agent.stdout!r}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
