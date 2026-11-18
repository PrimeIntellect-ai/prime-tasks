#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import codecs
import os
import random
import secrets
import shutil
import string
import subprocess
import tempfile
import uuid


def run_sanitizer(data):
    return subprocess.run(
        ["/home/user/config_sanitizer"],
        input=data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )


def random_ipv4(rng):
    return ".".join(str(rng.randrange(256)) for _ in range(4))


def random_username(rng):
    alphabet = string.ascii_lowercase + string.digits
    return "".join(rng.choice(alphabet) for _ in range(rng.randint(1, 16)))


def safe_command(rng):
    if rng.randrange(2) == 0:
        return "useradd " + random_username(rng)
    network = random_ipv4(rng)
    gateway = random_ipv4(rng)
    while gateway == "10.99.99.99":
        gateway = random_ipv4(rng)
    return f"ip route add {network}/{rng.randrange(33)} via {gateway}"


def test_config_sanitizer_artifacts_and_original_corpus():
    sanitizer_path = "/home/user/config_sanitizer"
    source_path = "/home/user/config_sanitizer.c"
    assert os.path.isfile(source_path), f"Sanitizer source not found at {source_path}"
    assert os.path.isfile(sanitizer_path), f"Sanitizer binary not found at {sanitizer_path}"
    assert os.access(sanitizer_path, os.X_OK), f"Sanitizer binary is not executable at {sanitizer_path}"
    with open(sanitizer_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "config_sanitizer is not a compiled ELF binary"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
                   if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
                  if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failed = []
    for path in clean_files:
        with open(path, "rb") as f:
            if subprocess.run([sanitizer_path], stdin=f, capture_output=True, timeout=5).returncode != 0:
                clean_failed.append(os.path.basename(path))

    evil_bypassed = []
    for path in evil_files:
        with open(path, "rb") as f:
            if subprocess.run([sanitizer_path], stdin=f, capture_output=True, timeout=5).returncode == 0:
                evil_bypassed.append(os.path.basename(path))

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean rejected: {', '.join(clean_failed)}")
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    assert not errors, " | ".join(errors)


def test_config_sanitizer_generated_adversarial_corpus():
    rng = random.Random(secrets.randbits(256))

    clean = [b"", b"\n", b"\n\n", b"useradd a", b"useradd z9\n"]
    for _ in range(300):
        commands = [safe_command(rng) for _ in range(rng.randint(1, 6))]
        lines = []
        for command in commands:
            if rng.randrange(4) == 0:
                lines.append("")
            lines.append(command)
            if rng.randrange(5) == 0:
                lines.append("")
        text = "\n".join(lines)
        if rng.randrange(2):
            text += "\n"
        clean.append(text.encode())

    evil = [
        b"useradd A", b"useradd abc_def", b"useradd abc-def", b"useradd ",
        b"useradd abc extra", b"useradd abc ", b" useradd abc", b"useradd\tabc",
        b"ip route add 256.1.1.1/24 via 1.1.1.1",
        b"ip route add 1.1.1.1/33 via 2.2.2.2",
        b"ip route add 1.1.1/24 via 2.2.2.2",
        b"ip route add 1.1.1.1/24 via 10.99.99.99",
        b"ip route add 1.1.1.1/24 via 2.2.2.999",
        b"rm -rf /", b"echo hello", b"useradd root;id", b"useradd root&id",
        b"useradd root|id", b"useradd $USER", b"useradd root>file", b"useradd root<file",
        b"useradd abc\x00ignored",
    ]

    bad_builders = [
        lambda: f"useradd {random_username(rng)};{rng.choice(['id', 'true', 'echo x'])}",
        lambda: f"useradd {random_username(rng)}&id",
        lambda: f"useradd {random_username(rng)}|cat",
        lambda: f"useradd ${random_username(rng)}",
        lambda: "useradd " + "a" * rng.randint(17, 50),
        lambda: "useradd " + random_username(rng).upper(),
        lambda: "useradd " + random_username(rng) + "-x",
        lambda: "useradd  " + random_username(rng),
        lambda: f"ip route add {rng.randrange(256)}.{rng.randrange(256)}.{rng.randrange(256)}.256/24 via {random_ipv4(rng)}",
        lambda: f"ip route add {random_ipv4(rng)}/{rng.randint(33, 999)} via {random_ipv4(rng)}",
        lambda: f"ip route add {random_ipv4(rng)}/{rng.randrange(33)} via 10.99.99.99",
        lambda: f"ip route add {random_ipv4(rng)}/{rng.randrange(33)} via {random_ipv4(rng)} extra",
        lambda: f"ip  route add {random_ipv4(rng)}/{rng.randrange(33)} via {random_ipv4(rng)}",
        lambda: f"route add {random_ipv4(rng)}/{rng.randrange(33)} via {random_ipv4(rng)}",
        lambda: rng.choice(["touch /tmp/x", "uname -a", "cat /etc/passwd", "true"]),
    ]
    for _ in range(400):
        bad = rng.choice(bad_builders)()
        prefix = [safe_command(rng) for _ in range(rng.randrange(3))]
        suffix = [safe_command(rng) for _ in range(rng.randrange(3))]
        evil.append(("\n".join(prefix + [bad] + suffix) + ("\n" if rng.randrange(2) else "")).encode())

    rejected_clean = []
    for index, data in enumerate(clean):
        result = run_sanitizer(data)
        if result.returncode != 0:
            rejected_clean.append((index, data[:160], result.returncode))

    accepted_evil = []
    for index, data in enumerate(evil):
        result = run_sanitizer(data)
        if result.returncode == 0:
            accepted_evil.append((index, data[:160]))

    assert not rejected_clean, f"Sanitizer rejected generated safe inputs: {rejected_clean[:5]}"
    assert not accepted_evil, f"Sanitizer accepted generated unsafe inputs: {accepted_evil[:5]}"


def test_provision_daemon_original_and_generated_inputs():
    daemon_path = "/home/user/provision_daemon.sh"
    log_path = "/home/user/provision.log"
    assert os.path.isfile(daemon_path), f"Provision daemon not found at {daemon_path}"
    assert os.access(daemon_path, os.X_OK), f"Provision daemon is not executable at {daemon_path}"

    if os.path.exists(log_path):
        os.remove(log_path)
    original = "/app/corpus/clean/clean_1.txt"
    result = subprocess.run([daemon_path, original], capture_output=True, timeout=5)
    assert result.returncode == 0, f"Provision daemon failed with exit code {result.returncode}"
    with open(log_path) as f:
        assert f.read().strip().splitlines() == [
            "[SUCCESS] Applied: useradd jdoe",
            "[SUCCESS] Applied: ip route add 192.168.1.0/24 via 10.0.0.1",
        ]

    rng = random.Random(secrets.randbits(256))
    commands = [safe_command(rng) for _ in range(25)]
    contents = []
    for command in commands:
        if rng.randrange(3) == 0:
            contents.append("")
        contents.append(command)
    contents.append("")

    with tempfile.NamedTemporaryFile("w", delete=False) as f:
        f.write("\n".join(contents))
        generated_path = f.name
    try:
        if os.path.exists(log_path):
            os.remove(log_path)
        result = subprocess.run([daemon_path, generated_path], capture_output=True, timeout=10)
        assert result.returncode == 0, result.stderr.decode(errors="replace")
        assert os.path.exists(log_path), f"Log file {log_path} was not created"
        with open(log_path) as f:
            actual = f.read().splitlines()
        expected = [f"[SUCCESS] Applied: {command}" for command in commands]
        assert actual == expected, f"Generated daemon log mismatch. Got {actual!r}"
    finally:
        os.unlink(generated_path)


def encode_for_decoder(text):
    return base64.b64encode(codecs.encode(text, "rot_13").encode())


def clear_worktree(path):
    for name in os.listdir(path):
        if name == ".git":
            continue
        target = os.path.join(path, name)
        if os.path.isdir(target) and not os.path.islink(target):
            shutil.rmtree(target)
        else:
            os.unlink(target)


def commit_all(clone_dir, message, amend=False):
    subprocess.run(["git", "add", "-A"], cwd=clone_dir, check=True, capture_output=True)
    args = ["git", "commit", "-m", message]
    if amend:
        args.insert(2, "--amend")
    subprocess.run(args, cwd=clone_dir, check=True, capture_output=True)


def push_branch(clone_dir, branch):
    return subprocess.run(
        ["git", "push", "origin", f"HEAD:refs/heads/{branch}"],
        cwd=clone_dir,
        capture_output=True,
        timeout=20,
    )


def test_git_hook_generated_pushes():
    repo_path = "/home/user/infra-configs.git"
    hook_path = os.path.join(repo_path, "hooks", "pre-receive")
    assert os.path.isdir(repo_path), f"Git repo not found at {repo_path}"
    assert subprocess.run(["git", "rev-parse", "--is-bare-repository"], cwd=repo_path,
                          capture_output=True, text=True).stdout.strip() == "true"
    assert os.path.isfile(hook_path), f"pre-receive hook not found at {hook_path}"
    assert os.access(hook_path, os.X_OK), "pre-receive hook is not executable"

    rng = random.Random(secrets.randbits(256))
    token = uuid.uuid4().hex
    evil_branch = "verify-evil-" + token
    safe_branch = "verify-safe-" + token

    with tempfile.TemporaryDirectory() as tmpdir:
        clone_dir = os.path.join(tmpdir, "clone")
        subprocess.run(["git", "clone", repo_path, clone_dir], check=True, capture_output=True)
        subprocess.run(["git", "config", "user.name", "Verifier"], cwd=clone_dir, check=True)
        subprocess.run(["git", "config", "user.email", "verifier@example.invalid"], cwd=clone_dir, check=True)

        subprocess.run(["git", "checkout", "--orphan", evil_branch], cwd=clone_dir, check=True, capture_output=True)
        clear_worktree(clone_dir)
        initial_evil = f"useradd {random_username(rng)}; id\n"
        with open(os.path.join(clone_dir, "first.enc"), "wb") as f:
            f.write(encode_for_decoder(initial_evil))
        commit_all(clone_dir, "initial malicious encoded config")
        rejected = push_branch(clone_dir, evil_branch)
        assert rejected.returncode != 0, "Hook accepted a malicious .enc file on an initial branch push"

        subprocess.run(["git", "checkout", "--orphan", safe_branch], cwd=clone_dir, check=True, capture_output=True)
        clear_worktree(clone_dir)
        safe_one = safe_command(rng) + "\n" + safe_command(rng) + "\n"
        safe_two = safe_command(rng) + "\n"
        with open(os.path.join(clone_dir, "alpha.enc"), "wb") as f:
            f.write(encode_for_decoder(safe_one))
        with open(os.path.join(clone_dir, "beta.enc"), "wb") as f:
            f.write(encode_for_decoder(safe_two))
        with open(os.path.join(clone_dir, "ignored.txt"), "w") as f:
            f.write("useradd bad; rm -rf /\n")
        commit_all(clone_dir, "safe encoded configs")
        accepted = push_branch(clone_dir, safe_branch)
        assert accepted.returncode == 0, accepted.stderr.decode(errors="replace")

        with open(os.path.join(clone_dir, "new.enc"), "wb") as f:
            f.write(encode_for_decoder(f"ip route add {random_ipv4(rng)}/24 via 10.99.99.99\n"))
        commit_all(clone_dir, "add one malicious file among safe files")
        rejected = push_branch(clone_dir, safe_branch)
        assert rejected.returncode != 0, "Hook accepted a push containing a newly added malicious .enc file"

        with open(os.path.join(clone_dir, "new.enc"), "wb") as f:
            f.write(encode_for_decoder(safe_command(rng) + "\n"))
        commit_all(clone_dir, "replace rejected content with safe content", amend=True)
        accepted = push_branch(clone_dir, safe_branch)
        assert accepted.returncode == 0, accepted.stderr.decode(errors="replace")

        with open(os.path.join(clone_dir, "alpha.enc"), "wb") as f:
            f.write(encode_for_decoder("rm -rf /\n"))
        commit_all(clone_dir, "malicious modification")
        rejected = push_branch(clone_dir, safe_branch)
        assert rejected.returncode != 0, "Hook accepted a malicious modification to an existing .enc file"

        with open(os.path.join(clone_dir, "alpha.enc"), "wb") as f:
            f.write(encode_for_decoder(safe_command(rng) + "\n"))
        commit_all(clone_dir, "safe modification", amend=True)
        accepted = push_branch(clone_dir, safe_branch)
        assert accepted.returncode == 0, accepted.stderr.decode(errors="replace")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
