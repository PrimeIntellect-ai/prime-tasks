#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import pwd
import random
import shutil
import subprocess
import tempfile


def run_as_user(command):
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return subprocess.run(
        command,
        capture_output=True,
        text=True,
        timeout=30,
        preexec_fn=demote,
    )


def test_finder_executable_exists():
    target = "/home/user/finder"
    source = "/home/user/finder.cpp"

    assert os.path.isfile(target), f"Agent target {target} does not exist."
    assert os.access(target, os.X_OK), f"Agent target {target} is not executable."
    assert not os.path.islink(target), f"Agent target {target} must be a compiled binary, not a symlink."
    with open(target, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Agent target {target} is not an ELF binary."

    assert os.path.isfile(source), f"Required C++ source {source} does not exist."
    assert not os.path.islink(source), f"Required C++ source {source} must be a regular file."


def test_fuzz_equivalence():
    oracle = "/app/oracle_finder"
    target = "/home/user/finder"
    source = "/home/user/finder.cpp"

    assert os.path.isfile(oracle), f"Oracle {oracle} does not exist."
    assert os.access(oracle, os.X_OK), f"Oracle {oracle} is not executable."
    assert not filecmp.cmp(target, oracle, shallow=False), "Target is byte-identical to the legacy oracle."

    with open(source, "rb") as f:
        source_bytes = f.read()
    assert b"oracle_finder" not in source_bytes, "Source must not delegate to the legacy oracle."

    build_dir = tempfile.mkdtemp(prefix="finder-build-")
    os.chmod(build_dir, 0o755)
    rebuilt = os.path.join(build_dir, "finder")
    compile_proc = subprocess.run(
        ["g++", "-O3", "-std=c++17", source, "-o", rebuilt],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert compile_proc.returncode == 0, (
        f"finder.cpp does not compile as C++17:\n{compile_proc.stdout}{compile_proc.stderr}"
    )

    random.seed(42)
    cases = []
    for _ in range(100):
        frame_index = random.randint(0, 299)
        q1 = random.randint(0, 10000000)
        q2 = random.randint(0, 10000000)
        q3 = random.randint(0, 10000000)
        cases.append([str(frame_index), f"{q1},{q2},{q3}"])

    expected = []
    for args in cases:
        oracle_proc = subprocess.run([oracle] + args, capture_output=True, text=True, timeout=30)
        assert oracle_proc.returncode == 0, (
            f"Oracle failed on input {args} with error: {oracle_proc.stderr}"
        )
        expected.append(oracle_proc.stdout)

    hidden_dir = tempfile.mkdtemp(prefix="hidden-oracle-")
    os.chmod(hidden_dir, 0o700)
    hidden_oracle = os.path.join(hidden_dir, "oracle_finder")
    os.rename(oracle, hidden_oracle)

    try:
        for i, (args, oracle_out) in enumerate(zip(cases, expected), 1):
            for executable, label in ((target, "Target"), (rebuilt, "Recompiled finder.cpp")):
                proc = run_as_user([executable] + args)
                assert proc.returncode == 0, (
                    f"{label} failed on input {args} with error: {proc.stderr}"
                )

                # Preserve the original normalized equivalence assertion.
                assert proc.stdout.strip() == oracle_out.strip(), (
                    f"Mismatch on iteration {i}:\n"
                    f"Input arguments: frame_index={args[0]}, query_vector='{args[1]}'\n"
                    f"Oracle output: '{oracle_out.strip()}'\n"
                    f"{label} output: '{proc.stdout.strip()}'"
                )
                # The task additionally requires exact output, including the newline.
                assert proc.stdout == oracle_out, (
                    f"{label} output was not bit-exact on input {args}."
                )
    finally:
        os.rename(hidden_oracle, oracle)
        shutil.rmtree(hidden_dir, ignore_errors=True)
        shutil.rmtree(build_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
