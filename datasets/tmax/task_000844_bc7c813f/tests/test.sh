#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import shutil
import stat
import struct
import subprocess
import tempfile

import pytest

ORACLE_PATH = "/app/bin/legacy_tracker"
AGENT_PATH = "/home/user/tracker/new_tracker"
SOURCE_PATH = "/home/user/tracker/main.go"
TRACKER_DIR = "/home/user/tracker"


def generate_trkv(seed):
    rng = random.Random(seed)
    out = bytearray(b"TRKV")
    file_count = rng.randint(0, 10)
    out.extend(struct.pack("<H", file_count))

    for _ in range(file_count):
        filename_len = rng.randint(1, 20)
        filename = "".join(rng.choices("abcdefghijklmnopqrstuvwxyz0123456789_.", k=filename_len))
        out.extend(struct.pack("B", filename_len))
        out.extend(filename.encode("ascii"))

        content_len = rng.randint(0, 500)
        content = bytearray()
        while len(content) < content_len:
            choice = rng.random()
            if choice < 0.05:
                pass_len = rng.randint(1, 10)
                pass_str = "PASS=" + "".join(rng.choices(
                    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",
                    k=pass_len,
                ))
                content.extend(pass_str.encode("ascii"))
            elif choice < 0.10:
                content.extend(b"\r\n")
            else:
                content.append(rng.choice(
                    b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 \t\n!@#$%^&*()"
                ))

        content = content[:content_len]
        out.extend(struct.pack("<I", content_len))
        out.extend(content)

    return bytes(out)


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.digest()


def run_program(argv, input_data, **kwargs):
    try:
        return subprocess.run(
            argv,
            input=input_data,
            capture_output=True,
            timeout=5,
            **kwargs,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Program timed out: {argv[0]}")


def assert_matches(proc, expected_returncode, expected_stdout, case_label, program_label):
    assert proc.returncode == expected_returncode, (
        f"Return code mismatch for {program_label} on {case_label}. "
        f"Oracle: {expected_returncode}, candidate: {proc.returncode}"
    )
    if proc.stdout != expected_stdout:
        mismatch_idx = -1
        for j in range(min(len(expected_stdout), len(proc.stdout))):
            if expected_stdout[j] != proc.stdout[j]:
                mismatch_idx = j
                break
        if mismatch_idx == -1:
            mismatch_idx = min(len(expected_stdout), len(proc.stdout))
        pytest.fail(
            f"Output mismatch for {program_label} on {case_label}.\n"
            f"Oracle output length: {len(expected_stdout)} bytes\n"
            f"Candidate output length: {len(proc.stdout)} bytes\n"
            f"First mismatch at byte index {mismatch_idx}."
        )


def test_fuzz_equivalence_and_go_source():
    assert os.path.exists(AGENT_PATH), f"Agent program missing at {AGENT_PATH}. Did you compile it?"
    assert not os.path.islink(AGENT_PATH), "new_tracker must be a real executable, not a symlink."
    assert stat.S_ISREG(os.stat(AGENT_PATH).st_mode), "new_tracker must be a regular file."
    assert os.access(AGENT_PATH, os.X_OK), f"Agent program not executable at {AGENT_PATH}."

    assert os.path.exists(SOURCE_PATH), f"Go source missing at {SOURCE_PATH}."
    assert not os.path.islink(SOURCE_PATH), "main.go must be a real source file, not a symlink."
    assert stat.S_ISREG(os.stat(SOURCE_PATH).st_mode), "main.go must be a regular file."

    assert digest(AGENT_PATH) != digest(ORACLE_PATH), "new_tracker must not be a copy of the legacy binary."

    with tempfile.TemporaryDirectory(prefix="tracker_verify_") as temp_dir:
        rebuilt_path = os.path.join(temp_dir, "rebuilt_tracker")
        env = os.environ.copy()
        env["CGO_ENABLED"] = "0"
        build = subprocess.run(
            ["go", "build", "-o", rebuilt_path, SOURCE_PATH],
            cwd=TRACKER_DIR,
            env=env,
            capture_output=True,
            text=True,
            timeout=60,
        )
        assert build.returncode == 0, f"main.go did not build successfully:\n{build.stderr}"
        assert os.path.isfile(rebuilt_path) and os.access(rebuilt_path, os.X_OK)
        assert digest(rebuilt_path) != digest(ORACLE_PATH), "Rebuilt source produced a copy of the legacy binary."

        # Retain the original fixed corpus and add unpredictable cases so a
        # submission cannot specialize itself to the verifier's known seeds.
        random_seeds = [int.from_bytes(os.urandom(16), "big") for _ in range(100)]
        cases = [(f"fixed seed {i}", generate_trkv(i)) for i in range(100)]
        cases += [(f"random case {i}", generate_trkv(seed)) for i, seed in enumerate(random_seeds)]

        expected = []
        for label, input_data in cases:
            proc = run_program([ORACLE_PATH], input_data)
            expected.append((label, input_data, proc.returncode, proc.stdout))

        # Re-run the source-built artifact in a filesystem containing only that
        # executable. This ensures main.go implements the conversion itself
        # rather than forwarding to the legacy program or another helper.
        jail_dir = os.path.join(temp_dir, "jail")
        os.mkdir(jail_dir)
        jailed_candidate = os.path.join(jail_dir, "candidate")
        shutil.copy2(rebuilt_path, jailed_candidate)
        os.chmod(jailed_candidate, 0o755)

        def enter_jail():
            os.chroot(jail_dir)
            os.chdir("/")

        oracle_mode = stat.S_IMODE(os.stat(ORACLE_PATH).st_mode)
        with open(ORACLE_PATH, "rb") as f:
            oracle_bytes = f.read()

        # Also remove the oracle while exercising the submitted executable, so
        # a direct forwarding wrapper cannot pass the original assertions.
        os.unlink(ORACLE_PATH)
        try:
            for label, input_data, expected_rc, expected_stdout in expected:
                rebuilt_proc = run_program(
                    ["/candidate"], input_data, preexec_fn=enter_jail
                )
                assert_matches(rebuilt_proc, expected_rc, expected_stdout, label, "source-built program")

                agent_proc = run_program([AGENT_PATH], input_data)
                assert_matches(agent_proc, expected_rc, expected_stdout, label, "new_tracker")
        finally:
            restore_tmp = ORACLE_PATH + ".restore"
            with open(restore_tmp, "wb") as f:
                f.write(oracle_bytes)
            os.chmod(restore_tmp, oracle_mode)
            os.replace(restore_tmp, ORACLE_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
