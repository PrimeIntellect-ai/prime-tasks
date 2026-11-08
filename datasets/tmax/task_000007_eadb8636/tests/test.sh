#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "numpy:numpy"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import pytest
import numpy as np

ORACLE_PATH = "/app/cleaner_oracle"
AGENT_PATH = "/home/user/cleaner"
SOURCE_PATH = "/home/user/cleaner.c"


def test_agent_binary_exists():
    assert os.path.exists(AGENT_PATH), f"Agent binary {AGENT_PATH} not found. Did you compile your C code?"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary {AGENT_PATH} is not executable."


def test_source_and_binary_are_real_files():
    source_stat = os.lstat(SOURCE_PATH)
    agent_stat = os.lstat(AGENT_PATH)
    assert stat.S_ISREG(source_stat.st_mode), f"{SOURCE_PATH} must be a regular C source file."
    assert stat.S_ISREG(agent_stat.st_mode), f"{AGENT_PATH} must be a regular compiled file."
    assert source_stat.st_size > 0, f"{SOURCE_PATH} is empty."
    with open(AGENT_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{AGENT_PATH} is not a compiled ELF executable."


def test_agent_is_not_copied_oracle():
    with open(ORACLE_PATH, "rb") as f:
        oracle_bytes = f.read()
    with open(AGENT_PATH, "rb") as f:
        agent_bytes = f.read()
    assert agent_bytes != oracle_bytes, "The submitted executable is byte-identical to cleaner_oracle."


def test_fuzz_equivalence():
    np.random.seed(1337)

    num_tests = 50
    for i in range(num_tests):
        # Length ranging from 0 to 100,000 integers
        length = np.random.randint(0, 100001)

        if length > 0:
            # Generate uniformly distributed 32-bit signed integers
            arr = np.random.randint(np.iinfo(np.int32).min, np.iinfo(np.int32).max, size=length, dtype=np.int32)

            # Inject the special value -9999 occasionally to ensure that logic is tested
            inject_mask = np.random.rand(length) < 0.05
            arr[inject_mask] = -9999

            input_bytes = arr.tobytes()
        else:
            input_bytes = b""

        oracle_proc = subprocess.run([ORACLE_PATH], input=input_bytes, capture_output=True)
        agent_proc = subprocess.run([AGENT_PATH], input=input_bytes, capture_output=True)

        assert oracle_proc.returncode == 0, f"Oracle failed on test case {i}."
        assert agent_proc.returncode == 0, f"Agent program failed with return code {agent_proc.returncode} on test case {i}."

        if oracle_proc.stdout != agent_proc.stdout:
            # Find the first differing byte to provide a helpful error message
            oracle_out = oracle_proc.stdout
            agent_out = agent_proc.stdout

            min_len = min(len(oracle_out), len(agent_out))
            diff_idx = -1
            for j in range(min_len):
                if oracle_out[j] != agent_out[j]:
                    diff_idx = j
                    break

            if diff_idx == -1:
                diff_idx = min_len

            element_idx = diff_idx // 4

            pytest.fail(
                f"Mismatch on test case {i} (input length {length} integers).\n"
                f"Outputs differ starting at byte index {diff_idx} (corresponding to input integer index {element_idx}).\n"
                f"Oracle output length: {len(oracle_out)} bytes.\n"
                f"Agent output length: {len(agent_out)} bytes."
            )


def stage_binary(binary, root):
    os.chmod(root, 0o755)
    staged = os.path.join(root, "cleaner")
    shutil.copy2(binary, staged)
    os.chmod(staged, 0o755)

    ldd = subprocess.run(
        ["runuser", "-u", "nobody", "--", "ldd", binary],
        capture_output=True,
        text=True,
    )
    text = ldd.stdout + "\n" + ldd.stderr
    if ldd.returncode != 0 and "not a dynamic executable" not in text and "statically linked" not in text:
        pytest.fail(f"Could not determine runtime libraries for {binary}: {text}")

    for library in set(re.findall(r"(?:=>\s*)?(/[^^\s()]+)", text)):
        if not os.path.isfile(library):
            continue
        destination = os.path.join(root, library.lstrip("/"))
        os.makedirs(os.path.dirname(destination), mode=0o755, exist_ok=True)
        shutil.copy2(library, destination)
        os.chmod(destination, 0o755)


def expected_output(arr):
    values = arr.astype(np.float32) * np.float32(0.0625)
    bits = values.view(np.uint32).copy()
    bits[arr == np.int32(-9999)] = np.uint32(0x7FC00000)
    return bits.tobytes()


def run_isolated(root, input_bytes):
    return subprocess.run(
        ["chroot", "--userspec=65534:65534", root, "/cleaner"],
        input=input_bytes,
        capture_output=True,
        timeout=15,
    )


@pytest.fixture(scope="session")
def isolated_artifacts(tmp_path_factory):
    base = tmp_path_factory.mktemp("isolated_cleaners")
    rebuilt = str(base / "rebuilt")
    compile_proc = subprocess.run(
        ["gcc", "-O2", "-std=c11", "-static", SOURCE_PATH, "-lm", "-o", rebuilt],
        cwd="/home/user",
        capture_output=True,
        text=True,
    )
    assert compile_proc.returncode == 0, (
        f"The submitted source could not be independently compiled:\n{compile_proc.stderr}"
    )

    rebuilt_root = str(base / "rebuilt_root")
    agent_root = str(base / "agent_root")
    os.mkdir(rebuilt_root)
    os.mkdir(agent_root)
    stage_binary(rebuilt, rebuilt_root)
    stage_binary(AGENT_PATH, agent_root)
    return rebuilt_root, agent_root


def test_source_and_compiled_program_work_without_oracle(isolated_artifacts):
    rebuilt_root, agent_root = isolated_artifacts
    rng = np.random.RandomState(90210)
    random_values = rng.randint(
        np.iinfo(np.int32).min,
        np.iinfo(np.int32).max,
        size=4096,
        dtype=np.int32,
    )
    random_values[::97] = -9999

    cases = [
        np.array([], dtype=np.int32),
        np.array([
            np.iinfo(np.int32).min, -16777217, -10000, -9999, -9998, -1,
            0, 1, 15, 16, 17, 16777217, np.iinfo(np.int32).max
        ], dtype=np.int32),
        random_values,
    ]

    for case_index, arr in enumerate(cases):
        wanted = expected_output(arr)
        for label, root in (("rebuilt source", rebuilt_root), ("submitted executable", agent_root)):
            proc = run_isolated(root, arr.tobytes())
            assert proc.returncode == 0, (
                f"The {label} failed in an isolated filesystem on case {case_index}: "
                f"return code {proc.returncode}, stderr={proc.stderr!r}"
            )
            assert proc.stdout == wanted, (
                f"The {label} produced incorrect output without access to cleaner_oracle "
                f"on case {case_index}."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
