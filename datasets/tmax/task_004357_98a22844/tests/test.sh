#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import random
import secrets
import shutil
import string
import subprocess
import tempfile


def test_repo_git_exists():
    assert os.path.isdir("/home/user/repo.git"), "/home/user/repo.git directory does not exist"
    config_path = "/home/user/repo.git/config"
    assert os.path.exists(config_path), "Git config not found in /home/user/repo.git"
    with open(config_path, "r") as f:
        assert "bare = true" in f.read().lower(), "/home/user/repo.git is not a bare repository"


def test_post_receive_hook_exists_and_executable():
    hook_path = "/home/user/repo.git/hooks/post-receive"
    assert os.path.exists(hook_path), "post-receive hook does not exist"
    assert os.access(hook_path, os.X_OK), "post-receive hook is not executable"


def test_workspace_exists():
    assert os.path.isdir("/home/user/workspace/.git"), "/home/user/workspace is not a git repository"
    assert os.path.exists("/home/user/workspace/filter.go"), "filter.go not found in workspace"


def test_filter_binary_exists():
    path = "/home/user/filter"
    assert os.path.isfile(path), "/home/user/filter binary does not exist"
    assert os.access(path, os.X_OK), "/home/user/filter is not executable"
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/filter is not an ELF binary"


def _isolated_preexec(root):
    def isolate():
        os.chroot(root)
        os.chdir("/")
        os.setgroups([])
        os.setgid(65534)
        os.setuid(65534)
    return isolate


def test_fuzz_equivalence():
    oracle_path = "/app/legacy_filter"
    agent_path = "/home/user/filter"

    assert os.path.isfile(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent binary missing at {agent_path}"
    assert not filecmp.cmp(oracle_path, agent_path, shallow=False), "Submitted binary is identical to the oracle"

    charset = string.ascii_letters + string.digits + string.punctuation + " "
    rng = secrets.SystemRandom()
    cases = []

    for i in range(3000):
        length = rng.randint(5, 150)
        value = "".join(rng.choice(charset) for _ in range(length))
        if i % 4 == 0:
            position = rng.randint(0, len(value))
            value = value[:position] + "FATAL" + value[position:]
        cases.append(value)

    # Obtain answers before entering the isolated environment. The corpus is
    # generated from OS entropy and is not reproducible by the submission.
    expected = []
    for value in cases:
        result = subprocess.run(
            [oracle_path, value], capture_output=True, text=True, timeout=5
        )
        assert result.returncode == 0, f"Oracle failed on input: {value!r}"
        expected.append(result.stdout.strip())

    # Run only the submitted ELF in a fresh chroot, as an unprivileged user.
    # This prevents it from delegating classifications to /app/legacy_filter
    # or to another executable copied elsewhere in the agent filesystem.
    with tempfile.TemporaryDirectory() as sandbox:
        isolated_agent = os.path.join(sandbox, "filter")
        shutil.copy2(agent_path, isolated_agent)
        os.chmod(sandbox, 0o755)
        os.chmod(isolated_agent, 0o755)

        for value, oracle_out in zip(cases, expected):
            result = subprocess.run(
                ["/filter", value],
                capture_output=True,
                text=True,
                timeout=5,
                preexec_fn=_isolated_preexec(sandbox),
            )
            assert result.returncode == 0, (
                f"Agent failed with status {result.returncode} on input: {value!r}\n"
                f"stderr: {result.stderr}"
            )
            agent_out = result.stdout.strip()
            assert oracle_out == agent_out, (
                f"Mismatch on input: {value!r}\n"
                f"Oracle output: {oracle_out}\n"
                f"Agent output: {agent_out}"
            )


def test_git_hook_functionality():
    workspace_dir = "/home/user/workspace"
    test_go_code = """package main
import "fmt"
func main() {
    fmt.Print("HOOK_TEST_SUCCESS")
}
"""
    with tempfile.TemporaryDirectory() as tmpdir:
        subprocess.run(["git", "clone", "/home/user/repo.git", tmpdir], check=True, capture_output=True)

        with open(os.path.join(tmpdir, "filter.go"), "w") as f:
            f.write(test_go_code)

        subprocess.run(["git", "add", "filter.go"], cwd=tmpdir, check=True, capture_output=True)
        subprocess.run(
            ["git", "-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-m", "Test hook"],
            cwd=tmpdir,
            check=True,
            capture_output=True,
        )
        subprocess.run(["git", "push", "origin", "main"], cwd=tmpdir, check=True, capture_output=True)

    agent_path = "/home/user/filter"
    assert os.path.exists(agent_path), "Agent binary missing after push"

    res = subprocess.run([agent_path, "dummy"], capture_output=True, text=True)
    assert "HOOK_TEST_SUCCESS" in res.stdout, "The post-receive hook did not correctly compile and deploy the pushed code"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
