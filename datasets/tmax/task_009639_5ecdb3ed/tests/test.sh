#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess

REPO_DIR = "/home/user/prng_repo"
HASH_FILE = "/home/user/bad_commit_hash.txt"
PATCH_FILE = "/home/user/fix.patch"


def run_git_command(args, cwd=REPO_DIR):
    result = subprocess.run(
        ["git"] + args,
        cwd=cwd,
        capture_output=True,
        text=True,
        check=True
    )
    return result.stdout.strip()


def expected_generate(seed, n):
    state = seed
    results = []
    for _ in range(n):
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        results.append(state)
    return results


def make_cases():
    cases = [
        [0, 0], [0, 1], [1, 8], [42, 3], [-1, 12],
        [0x7FFFFFFF, 16], [0x80000000, 16], [0xFFFFFFFF, 16]
    ]
    for _ in range(96):
        seed = secrets.randbits(32)
        if secrets.randbits(1):
            seed = -seed
        cases.append([seed, secrets.randbelow(32) + 1])
    return cases


def assert_prng_behavior(repo_dir, cases):
    runner = (
        "import json, sys\n"
        "import prng\n"
        "cases = json.load(sys.stdin)\n"
        "print(json.dumps([prng.generate(seed, n) for seed, n in cases]))\n"
    )
    proc = subprocess.run(
        ["python3", "-c", runner],
        cwd=str(repo_dir),
        input=json.dumps(cases),
        capture_output=True,
        text=True,
        timeout=20
    )
    assert proc.returncode == 0, f"PRNG execution failed:\n{proc.stderr}"
    try:
        actual = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"PRNG produced invalid output: {proc.stdout!r}") from exc
    expected = [expected_generate(seed, n) for seed, n in cases]
    assert actual == expected, "PRNG does not implement the required 31-bit recurrence."


def test_bad_commit_hash_correct():
    assert os.path.isfile(HASH_FILE), f"File {HASH_FILE} does not exist."

    with open(HASH_FILE, "r") as f:
        actual_hash = f.read().strip()

    expected_hash = run_git_command(["log", "--grep=Optimize bitmask and refactor step 137", "--format=%H"])

    assert actual_hash == expected_hash, f"Incorrect bad commit hash in {HASH_FILE}. Expected {expected_hash}, got {actual_hash}."


def test_repository_prng_is_fixed():
    prng_path = os.path.join(REPO_DIR, "prng.py")
    assert os.path.isfile(prng_path), f"File {prng_path} does not exist."
    assert stat.S_ISREG(os.lstat(prng_path).st_mode), f"{prng_path} is not a regular file."

    python_code = "import prng; print(prng.generate(42, 3))"
    py_proc = subprocess.run(
        ["python3", "-c", python_code],
        cwd=REPO_DIR,
        capture_output=True,
        text=True
    )
    expected_output = "[1804289383, 846930886, 1681692777]"
    actual_output = py_proc.stdout.strip()
    assert py_proc.returncode == 0, f"Repository PRNG failed to execute:\n{py_proc.stderr}"
    assert actual_output == expected_output, f"Repository prng.py is not fixed. Expected {expected_output}, got {actual_output}."

    assert_prng_behavior(REPO_DIR, make_cases())


def test_patch_exists_and_fixes_bug(tmp_path):
    assert os.path.isfile(PATCH_FILE), f"Patch file {PATCH_FILE} does not exist."

    temp_repo = tmp_path / "prng_repo"
    subprocess.run(["git", "clone", REPO_DIR, str(temp_repo)], check=True, capture_output=True)
    subprocess.run(["git", "reset", "--hard", "HEAD"], cwd=str(temp_repo), check=True, capture_output=True)

    apply_proc = subprocess.run(["git", "apply", PATCH_FILE], cwd=str(temp_repo), capture_output=True, text=True)
    assert apply_proc.returncode == 0, f"Patch failed to apply cleanly:\n{apply_proc.stderr}"

    python_code = "import prng; print(prng.generate(42, 3))"
    py_proc = subprocess.run(["python3", "-c", python_code], cwd=str(temp_repo), capture_output=True, text=True)

    expected_output = "[1804289383, 846930886, 1681692777]"
    actual_output = py_proc.stdout.strip()

    assert actual_output == expected_output, f"Patch did not restore the correct mathematical behavior. Expected {expected_output}, got {actual_output}."
    assert_prng_behavior(temp_repo, make_cases())
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
