#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import pwd
import random
import shlex
import shutil
import stat
import string
import subprocess
import tempfile

import pytest

ORACLE = "/app/log_obfuscator"
AGENT = "/home/user/obfuscator_clone"
SOURCE = "/home/user/obfuscator_clone.go"


def run_program(path, data, drop_privileges=False):
    kwargs = {}
    if drop_privileges:
        account = pwd.getpwnam("user")
        def demote():
            os.setgroups([])
            os.setgid(account.pw_gid)
            os.setuid(account.pw_uid)
        kwargs["preexec_fn"] = demote
    return subprocess.run(
        [path], input=data, capture_output=True, timeout=10, **kwargs
    )


def expected_output(data):
    return bytes((((value ^ 0x5A) + (index % 8)) & 0xFF)
                 for index, value in enumerate(data))


def assert_go_elf(path):
    info = os.stat(path, follow_symlinks=False)
    assert stat.S_ISREG(info.st_mode), f"Not a regular file: {path}"
    assert os.access(path, os.X_OK), f"Not executable: {path}"
    with open(path, "rb") as handle:
        assert handle.read(4) == b"\x7fELF", f"Not an ELF executable: {path}"
    result = subprocess.run(
        ["go", "version", "-m", path], capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, f"Not a Go executable: {result.stderr}"
    assert path in result.stdout and "go1" in result.stdout, "Missing Go build information"


def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE), f"Oracle missing: {ORACLE}"
    assert os.access(ORACLE, os.X_OK), f"Oracle not executable: {ORACLE}"
    assert os.path.isfile(AGENT), f"Agent binary missing: {AGENT}"
    assert os.access(AGENT, os.X_OK), f"Agent binary not executable: {AGENT}"

    assert hashlib.sha256(open(ORACLE, "rb").read()).digest() != hashlib.sha256(open(AGENT, "rb").read()).digest(), "Agent binary must not be the oracle"

    random.seed(42)
    charset = string.printable
    for _ in range(1000):
        length = random.randint(1, 1024)
        input_data = "".join(random.choice(charset) for _ in range(length)).encode("utf-8")
        oracle_proc = run_program(ORACLE, input_data)
        agent_proc = run_program(AGENT, input_data)
        assert oracle_proc.returncode == 0, f"Oracle failed on input: {input_data!r}"
        assert agent_proc.returncode == 0, f"Agent failed on input: {input_data!r}"
        if oracle_proc.stdout != agent_proc.stdout:
            pytest.fail(
                f"Mismatch found!\nInput (hex): {input_data.hex()}\n"
                f"Oracle output (hex): {oracle_proc.stdout.hex()}\n"
                f"Agent output (hex): {agent_proc.stdout.hex()}"
            )


def test_go_source_and_independent_behavior():
    assert os.path.isfile(SOURCE), f"Go source missing: {SOURCE}"
    assert stat.S_ISREG(os.stat(SOURCE, follow_symlinks=False).st_mode), "Go source must be a regular file"
    assert_go_elf(AGENT)

    source_text = open(SOURCE, "r", encoding="utf-8").read()
    forbidden = [
        '"os/exec"', '`os/exec`', '"syscall"', '`syscall`',
        '"plugin"', '`plugin`', 'import "C"', "import `C`",
        "//go:linkname", ".StartProcess", ".ForkExec", ".Command(",
        ".CommandContext(",
    ]
    for marker in forbidden:
        assert marker not in source_text, f"Go source delegates execution instead of implementing the transform: {marker}"

    with tempfile.TemporaryDirectory(prefix="verify-go-") as build_dir:
        isolated_source = os.path.join(build_dir, "main.go")
        rebuilt = os.path.join(build_dir, "obfuscator_clone")
        shutil.copyfile(SOURCE, isolated_source)
        env = os.environ.copy()
        env.update({
            "GO111MODULE": "off",
            "GOPATH": os.path.join(build_dir, "gopath"),
            "GOCACHE": os.path.join(build_dir, "gocache"),
        })
        build = subprocess.run(
            ["go", "build", "-o", rebuilt, isolated_source],
            cwd=build_dir, env=env, capture_output=True, text=True, timeout=60
        )
        assert build.returncode == 0, f"Go source does not compile independently:\n{build.stderr}"
        os.chmod(rebuilt, 0o755)
        assert_go_elf(rebuilt)

        hidden_oracle = f"/app/.log_obfuscator.verifier.{os.getpid()}"
        os.rename(ORACLE, hidden_oracle)
        old_mode = stat.S_IMODE(os.stat(hidden_oracle).st_mode)
        os.chmod(hidden_oracle, 0o700)
        try:
            cases = [
                b"", b"a", b"hello\n", bytes(range(256)),
                b"\x00" * 4097, b"\xff" * 4097,
            ]
            rng = random.Random(987654321)
            for _ in range(300):
                cases.append(os.urandom(rng.randint(0, 8192)))

            for data in cases:
                expected = expected_output(data)
                for candidate in (AGENT, rebuilt):
                    proc = run_program(candidate, data, drop_privileges=True)
                    assert proc.returncode == 0, f"{candidate} failed with code {proc.returncode}: {proc.stderr!r}"
                    assert proc.stdout == expected, (
                        f"Incorrect independent result from {candidate}\n"
                        f"Input: {data.hex()}\nExpected: {expected.hex()}\nGot: {proc.stdout.hex()}"
                    )
                    assert proc.stderr == b"", f"Unexpected stderr from {candidate}: {proc.stderr!r}"
        finally:
            os.chmod(hidden_oracle, old_mode)
            os.rename(hidden_oracle, ORACLE)


def test_hardened_sshd_config():
    path = "/home/user/hardened_sshd_config"
    assert os.path.isfile(path), f"Missing hardened config: {path}"

    with open(path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip() and not line.strip().startswith("#")]

    content = " ".join(lines)
    assert "PermitRootLogin no" in content or "permitrootlogin no" in content.lower(), "PermitRootLogin no is missing or commented out"
    assert "PermitEmptyPasswords no" in content or "permitemptypasswords no" in content.lower(), "PermitEmptyPasswords no is missing or commented out"
    assert "Protocol 1" not in content and "protocol 1" not in content.lower(), "Protocol 1 must be disabled"
    assert "MACs hmac-sha2-512,hmac-sha2-256" in content or "macs hmac-sha2-512,hmac-sha2-256" in content.lower(), "MACs are not correctly restricted to hmac-sha2-512,hmac-sha2-256"

    parsed = []
    for line_number, raw in enumerate(open(path, "r", encoding="utf-8"), 1):
        try:
            tokens = shlex.split(raw, comments=True, posix=True)
        except ValueError as exc:
            pytest.fail(f"Invalid SSH configuration syntax on line {line_number}: {exc}")
        if not tokens:
            continue
        assert len(tokens) >= 2, f"Directive without a value on line {line_number}"
        parsed.append((tokens[0].lower(), tokens[1:], line_number))

    required = {
        "permitrootlogin": ["no"],
        "permitemptypasswords": ["no"],
        "protocol": ["2"],
        "macs": ["hmac-sha2-512,hmac-sha2-256"],
    }
    for directive, expected in required.items():
        occurrences = [(args, line) for name, args, line in parsed if name == directive]
        assert len(occurrences) == 1, f"{directive} must occur exactly once as an active directive"
        args, line_number = occurrences[0]
        assert [arg.lower() for arg in args] == expected, f"Invalid {directive} value on line {line_number}: {args}"

    # Match and Include can change scope or import contradictory settings that this
    # standalone remediation file cannot safely validate.
    assert all(name not in {"match", "include"} for name, _, _ in parsed), "Match and Include are not allowed in the hardened standalone configuration"


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
