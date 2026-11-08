#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import pathlib
import random
import shutil
import stat
import subprocess
import tempfile


def generate_fuzz_inputs(n=1000):
    rng = random.SystemRandom()
    inputs = []
    for _ in range(n):
        hash_str = ''.join(rng.choice("0123456789abcdef") for _ in range(8))
        port = rng.randint(1, 65535)
        timestamp = rng.randint(1600000000, 1799999999)
        inputs.append(f"{hash_str}:{port}:{timestamp}")
    return inputs


def run_checked(path, inp):
    return subprocess.run(
        [path, inp], capture_output=True, text=True, timeout=10
    )


def run_in_chroot(root, executable, inp):
    return subprocess.run(
        ["chroot", "--userspec=65534:65534", root, executable, inp],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_token_gen_fuzz_equivalence():
    oracle_path = "/app/audit_oracle"
    agent_path = "/home/user/token_gen"
    source_path = "/home/user/token_gen.go"

    assert os.path.exists(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.path.exists(agent_path), f"Agent binary missing at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent binary at {agent_path} is not executable"

    agent_stat = os.lstat(agent_path)
    assert stat.S_ISREG(agent_stat.st_mode), "Agent executable must be a regular file, not a symlink or wrapper path"
    assert os.path.exists(source_path), f"Go source missing at {source_path}"
    source_stat = os.lstat(source_path)
    assert stat.S_ISREG(source_stat.st_mode), "token_gen.go must be a regular source file"
    assert not filecmp.cmp(agent_path, oracle_path, shallow=False), "Agent executable must not be a copy of the oracle"

    build_info = subprocess.run(
        ["go", "version", "-m", agent_path], capture_output=True, text=True, timeout=10
    )
    assert build_info.returncode == 0 and "go1" in build_info.stdout, "Agent executable is not a Go executable"

    source = pathlib.Path(source_path).read_text(encoding="utf-8")
    forbidden = {
        "/app/audit_oracle": "source must not invoke the legacy oracle",
        '"os/exec"': "source must not launch external programs",
        '"syscall"': "source must not use raw process syscalls",
        '"unsafe"': "source must be a clean Go implementation",
        'import "C"': "source must not delegate through cgo",
        "//go:linkname": "source must not use linkname delegation",
        "//go:embed": "source must not embed another executable",
        ".StartProcess(": "source must not launch external programs",
    }
    for needle, message in forbidden.items():
        assert needle not in source, message

    inputs = generate_fuzz_inputs(1000)

    with tempfile.TemporaryDirectory(prefix="token-verify-") as work:
        rebuilt = os.path.join(work, "rebuilt")
        env = os.environ.copy()
        env.update({"CGO_ENABLED": "0", "GO111MODULE": "off"})
        build = subprocess.run(
            ["go", "build", "-trimpath", "-o", rebuilt, source_path],
            capture_output=True,
            text=True,
            env=env,
            timeout=60,
        )
        assert build.returncode == 0, f"token_gen.go did not compile as clean Go: {build.stderr}"

        jail = os.path.join(work, "jail")
        os.mkdir(jail, 0o755)
        shutil.copyfile(agent_path, os.path.join(jail, "submitted"))
        shutil.copyfile(rebuilt, os.path.join(jail, "rebuilt"))
        os.chmod(os.path.join(jail, "submitted"), 0o555)
        os.chmod(os.path.join(jail, "rebuilt"), 0o555)
        os.chmod(jail, 0o555)

        for inp in inputs:
            oracle_res = run_checked(oracle_path, inp)
            assert oracle_res.returncode == 0, f"Oracle failed on input {inp}: {oracle_res.stderr}"
            oracle_out = oracle_res.stdout

            agent_res = run_in_chroot(jail, "/submitted", inp)
            assert agent_res.returncode == 0, f"Agent program failed independently on input {inp}: {agent_res.stderr}"
            assert oracle_out == agent_res.stdout, (
                f"Mismatch on input '{inp}'.\n"
                f"Oracle output: {repr(oracle_out)}\n"
                f"Agent output:  {repr(agent_res.stdout)}"
            )

            rebuilt_res = run_in_chroot(jail, "/rebuilt", inp)
            assert rebuilt_res.returncode == 0, f"Program rebuilt from token_gen.go failed on input {inp}: {rebuilt_res.stderr}"
            assert oracle_out == rebuilt_res.stdout, (
                f"Source mismatch on input '{inp}'.\n"
                f"Oracle output: {repr(oracle_out)}\n"
                f"Rebuilt output: {repr(rebuilt_res.stdout)}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
