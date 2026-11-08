#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import shutil
import subprocess
import tempfile

CHECK_TLS_PATH = "/home/user/check_tls.py"
PRE_RECEIVE_HOOK = "/home/user/proxy-repo.git/hooks/pre-receive"
REPO_PATH = "/home/user/proxy-repo.git"


def run(cmd, cwd=None, check=True):
    return subprocess.run(cmd, cwd=cwd, check=check, capture_output=True, text=True)


def check_tls(text):
    return subprocess.run(
        [CHECK_TLS_PATH], input=text, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True
    )


def assert_checker(text, weak):
    proc = check_tls(text)
    expected_code = 1 if weak else 0
    expected_stdout = "WEAK TLS DETECTED\n" if weak else ""
    assert proc.returncode == expected_code, (
        f"Checker returned {proc.returncode}, expected {expected_code} for {text!r}; "
        f"stdout={proc.stdout!r}, stderr={proc.stderr!r}"
    )
    assert proc.stdout == expected_stdout, (
        f"Checker stdout was {proc.stdout!r}, expected {expected_stdout!r} "
        f"for {text!r}"
    )


def test_check_tls_exists_executable_and_is_python():
    assert os.path.isfile(CHECK_TLS_PATH), f"{CHECK_TLS_PATH} does not exist."
    assert os.access(CHECK_TLS_PATH, os.X_OK), f"{CHECK_TLS_PATH} is not executable."
    compiled = run(["python3", "-m", "py_compile", CHECK_TLS_PATH], check=False)
    assert compiled.returncode == 0, f"check_tls.py is not valid Python: {compiled.stderr}"


def test_check_tls_logic_fixed_and_generated_inputs():
    # Preserve the original fixed assertions.
    fixed_cases = [
        ("ssl_protocols TLSv1.2 TLSv1.3;", False),
        ("ssl_protocols TLSv1.1 TLSv1.2;", True),
        ("ssl_protocols TLSv1 TLSv1.2;", True),
        ("ssl_protocols TLSv1; TLSv1.2;", True),
        ("TLSv1.3 only", False),
        ("TLSv1.1", True),
    ]
    for text, weak in fixed_cases:
        assert_checker(text, weak)

    # Generate values after the submitted implementation has been installed, so
    # a checker cannot pass by recognizing a fixed list of complete strings.
    rng = random.SystemRandom()
    for _ in range(36):
        marker = secrets.token_hex(12)
        safe_protocols = rng.choice([
            "TLSv1.2", "TLSv1.3", "TLSv1.2 TLSv1.3",
            "SSLv3-disabled", "no_protocol_token"
        ])
        safe_text = rng.choice([
            f"# {marker}\nssl_protocols {safe_protocols};\n",
            f"upstream {marker} {{ server 127.0.0.1; }}\n# {safe_protocols}",
            f"{marker}:{safe_protocols}:{secrets.token_hex(5)}",
        ])
        assert_checker(safe_text, False)

        weak_token = rng.choice([
            "TLSv1.1", "TLSv1;", "TLSv1 ",
            "TLSv1.1 TLSv1.3", "TLSv1;TLSv1.2"
        ])
        weak_text = rng.choice([
            f"# {marker}\nssl_protocols {weak_token};\n",
            f"server {{ set $tag {marker}; }}\n{weak_token}",
            f"{secrets.token_hex(7)}::{weak_token}::{marker}",
        ])
        assert_checker(weak_text, True)


def test_pre_receive_hook_exists_executable_and_is_bash():
    assert os.path.isfile(PRE_RECEIVE_HOOK), f"{PRE_RECEIVE_HOOK} does not exist."
    assert os.access(PRE_RECEIVE_HOOK, os.X_OK), f"{PRE_RECEIVE_HOOK} is not executable."
    with open(PRE_RECEIVE_HOOK, "rb") as hook:
        first_line = hook.readline().decode("utf-8", "replace")
    assert first_line.startswith("#!") and "bash" in first_line, (
        "pre-receive must be a bash script with a bash shebang"
    )


def test_git_push_hook_integration_varied_changes_and_refs():
    repo = tempfile.mkdtemp(prefix="tls-hook-")
    suffix = secrets.token_hex(8)
    primary_ref = f"refs/heads/verify-{suffix}"

    def write(path, content):
        full = os.path.join(repo, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w") as f:
            f.write(content)

    def commit(message):
        run(["git", "add", "-A"], cwd=repo)
        run(["git", "commit", "-m", message], cwd=repo)

    def push(*specs):
        return run(["git", "push", "origin", *specs], cwd=repo, check=False)

    def assert_rejected(result):
        assert result.returncode != 0, "Push containing a weak .conf file was accepted"
        combined = result.stdout + result.stderr
        assert "WEAK TLS DETECTED" in combined, (
            f"Rejected push did not report WEAK TLS DETECTED: {combined!r}"
        )

    try:
        run(["git", "init"], cwd=repo)
        run(["git", "remote", "add", "origin", REPO_PATH], cwd=repo)
        run(["git", "config", "user.email", f"{suffix}@example.com"], cwd=repo)
        run(["git", "config", "user.name", "Generated Hook Test"], cwd=repo)

        # Preserve the original successful initial push assertion.
        good_name = f"configs/good-{suffix}.conf"
        write(good_name, "server {\n listen 443 ssl;\n ssl_protocols TLSv1.2 TLSv1.3;\n}\n")
        commit("initial safe configuration")
        good_push = push(f"HEAD:{primary_ref}")
        assert good_push.returncode == 0, f"Pushing good config failed: {good_push.stderr}"

        # Preserve the original added-bad-file rejection and message assertions.
        bad_name = f"configs/bad-{suffix}.conf"
        write(bad_name, "server {\n listen 443 ssl;\n ssl_protocols TLSv1.1 TLSv1.2;\n}\n")
        commit("add weak configuration")
        assert_rejected(push(f"HEAD:{primary_ref}"))

        # Remove the rejected bad file and make a safe update; updates must not
        # be rejected merely because they are updates rather than ref creation.
        os.remove(os.path.join(repo, bad_name))
        write(good_name, f"# {secrets.token_hex(10)}\nssl_protocols TLSv1.3;\n")
        commit("safe update after rejection")
        safe_update = push(f"HEAD:{primary_ref}")
        assert safe_update.returncode == 0, safe_update.stderr

        # A weak modification of an existing .conf must be inspected.
        weak_context = secrets.token_hex(9)
        write(good_name, f"server {{\n # {weak_context}\n ssl_protocols TLSv1; TLSv1.3;\n}}\n")
        commit("weaken existing configuration")
        assert_rejected(push(f"HEAD:{primary_ref}"))

        # Restore it, while adding weak text only to a non-.conf file. The hook
        # must allow the push because only added/modified .conf files are checked.
        write(good_name, "ssl_protocols TLSv1.2;\n")
        write(f"notes-{suffix}.txt", f"documentation mentions TLSv1.1 {secrets.token_hex(6)}\n")
        commit("safe config and unrelated documentation")
        unrelated_push = push(f"HEAD:{primary_ref}")
        assert unrelated_push.returncode == 0, unrelated_push.stderr

        # New refs containing weak configurations must also be rejected.
        new_ref = f"refs/heads/new-weak-{secrets.token_hex(7)}"
        new_bad = f"sites/new-{secrets.token_hex(6)}.conf"
        write(new_bad, f"# {secrets.token_hex(8)}\nssl_protocols TLSv1.1;\n")
        commit("weak file on a newly created ref")
        assert_rejected(push(f"HEAD:{new_ref}"))
        os.remove(os.path.join(repo, new_bad))
        commit("remove rejected new-ref file")

        # Exercise multiple receive lines and multiple .conf files. The first ref
        # is safe while the second contains a weak file, so checking only the first
        # stdin line or only one changed file cannot pass.
        base_branch = f"base-{suffix}"
        safe_branch = f"multi-safe-{suffix}"
        weak_branch = f"multi-weak-{suffix}"
        run(["git", "branch", base_branch], cwd=repo)
        run(["git", "checkout", "-b", safe_branch], cwd=repo)
        write(f"multi/a-{suffix}.conf", f"# {secrets.token_hex(10)}\nssl_protocols TLSv1.2 TLSv1.3;\n")
        write(f"multi/b-{suffix}.conf", "ssl_protocols TLSv1.3;\n")
        commit("two safe configurations")

        run(["git", "checkout", "-b", weak_branch, base_branch], cwd=repo)
        write(f"multi/c-{suffix}.conf", "ssl_protocols TLSv1.2;\n")
        write(f"multi/d-{suffix}.conf", f"# {secrets.token_hex(11)}\nssl_protocols TLSv1 TLSv1.3;\n")
        commit("one safe and one weak configuration")

        remote_safe = f"refs/heads/receive-safe-{suffix}"
        remote_weak = f"refs/heads/receive-weak-{suffix}"
        multi_bad = push(f"{safe_branch}:{remote_safe}", f"{weak_branch}:{remote_weak}")
        assert_rejected(multi_bad)

        # Make the second ref safe and verify that the same multi-ref shape is
        # accepted when every changed configuration passes.
        write(f"multi/d-{suffix}.conf", "ssl_protocols TLSv1.2 TLSv1.3;\n")
        commit("make all configurations safe")
        multi_good = push(f"{safe_branch}:{remote_safe}", f"{weak_branch}:{remote_weak}")
        assert multi_good.returncode == 0, multi_good.stderr
    finally:
        shutil.rmtree(repo)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
