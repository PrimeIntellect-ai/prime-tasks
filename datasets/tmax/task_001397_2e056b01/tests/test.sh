#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import json
import os
import random
import shutil
import stat
import string
import subprocess
import tempfile

ORACLE_PATH = "/app/leaky_encoder"
AGENT_PATH = "/home/user/replicate"
SOURCE_PATH = "/home/user/replicate.go"


def generate_vocab(size=100):
    vocab = []
    for _ in range(size):
        length = random.randint(3, 10)
        word = ''.join(random.choices(string.ascii_letters + string.digits, k=length))
        vocab.append(word)
    return vocab


def generate_input(vocab):
    num_lines = random.randint(5, 50)
    lines = []
    for _ in range(num_lines):
        stage = random.choice(["train", "eval"])
        num_words = random.randint(3, 10)
        words = " ".join(random.choices(vocab, k=num_words))
        lines.append(json.dumps({"stage": stage, "text": words}))
    return "\n".join(lines) + "\n"


def make_isolated_binary(source_binary, root):
    destination = os.path.join(root, "replicate")
    shutil.copyfile(source_binary, destination)
    os.chmod(destination, 0o555)
    os.chmod(root, 0o555)


def run_isolated(root, inp):
    # The chroot contains only the submitted executable. In particular, the
    # oracle and the host /app directory are unavailable to the process.
    return subprocess.run(
        ["chroot", "--userspec=65534:65534", root, "/replicate"],
        input=inp,
        text=True,
        capture_output=True,
        timeout=10,
    )


def test_fuzz_equivalence():
    assert os.path.exists(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}. Did you compile it?"
    assert os.path.isfile(AGENT_PATH), f"Agent path at {AGENT_PATH} is not a regular file."
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary at {AGENT_PATH} is not executable."
    assert os.path.isfile(SOURCE_PATH), f"Go source not found at {SOURCE_PATH}."

    # Reject simply submitting the shipped reference executable.
    assert not filecmp.cmp(AGENT_PATH, ORACLE_PATH, shallow=False), \
        "Submitted binary is byte-identical to the reference encoder."

    with tempfile.TemporaryDirectory(prefix="clean-go-build-") as build_dir, \
         tempfile.TemporaryDirectory(prefix="agent-chroot-") as submitted_root, \
         tempfile.TemporaryDirectory(prefix="rebuilt-chroot-") as rebuilt_root:
        clean_source = os.path.join(build_dir, "replicate.go")
        rebuilt_binary = os.path.join(build_dir, "replicate")
        shutil.copyfile(SOURCE_PATH, clean_source)

        env = os.environ.copy()
        env["CGO_ENABLED"] = "0"
        build_proc = subprocess.run(
            ["go", "build", "-o", rebuilt_binary, clean_source],
            text=True,
            capture_output=True,
            env=env,
            timeout=120,
        )
        assert build_proc.returncode == 0, (
            "replicate.go did not build independently in a clean directory.\n"
            f"Stdout:\n{build_proc.stdout}\nStderr:\n{build_proc.stderr}"
        )
        assert not filecmp.cmp(rebuilt_binary, ORACLE_PATH, shallow=False), \
            "Binary rebuilt from replicate.go is byte-identical to the reference encoder."

        make_isolated_binary(AGENT_PATH, submitted_root)
        make_isolated_binary(rebuilt_binary, rebuilt_root)

        random.seed(42)
        vocab = generate_vocab(100)

        # Preserve the original 5000 randomized oracle comparisons, while
        # running both the submitted artifact and a clean source rebuild in
        # environments where they cannot invoke the oracle.
        for i in range(5000):
            inp = generate_input(vocab)

            oracle_proc = subprocess.run(
                [ORACLE_PATH], input=inp, text=True, capture_output=True, timeout=10
            )
            agent_proc = run_isolated(submitted_root, inp)
            rebuilt_proc = run_isolated(rebuilt_root, inp)

            assert oracle_proc.returncode == 0, f"Oracle failed unexpectedly on input:\n{inp}"
            assert agent_proc.returncode == 0, (
                f"Agent program failed (return code {agent_proc.returncode}) on input:\n{inp}"
                f"\nStderr:\n{agent_proc.stderr}"
            )
            assert rebuilt_proc.returncode == 0, (
                f"Clean rebuild failed (return code {rebuilt_proc.returncode}) on input:\n{inp}"
                f"\nStderr:\n{rebuilt_proc.stderr}"
            )

            assert agent_proc.stdout == oracle_proc.stdout, (
                f"Mismatch on iteration {i}.\nInput:\n{inp}\n"
                f"Oracle output:\n{oracle_proc.stdout}\nAgent output:\n{agent_proc.stdout}"
            )
            assert rebuilt_proc.stdout == oracle_proc.stdout, (
                f"Source rebuild mismatch on iteration {i}.\nInput:\n{inp}\n"
                f"Oracle output:\n{oracle_proc.stdout}\nRebuilt output:\n{rebuilt_proc.stdout}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
