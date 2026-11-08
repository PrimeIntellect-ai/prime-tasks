#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import os
import re
import secrets
import socket
import subprocess
import tempfile


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def test_git_repo_is_bare():
    repo_dir = "/home/user/sre-repo.git"
    assert os.path.isdir(repo_dir), f"Git repo directory {repo_dir} does not exist."

    config_path = os.path.join(repo_dir, "config")
    assert os.path.isfile(config_path), f"Git config missing in {repo_dir}."
    with open(config_path, "r") as f:
        content = f.read()
    assert "bare = true" in content.lower(), f"Repository at {repo_dir} is not a bare repository."

    result = subprocess.run(
        ["git", "--git-dir", repo_dir, "rev-parse", "--is-bare-repository"],
        text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0 and result.stdout.strip() == "true", "Repository is not a valid bare Git repository."


def test_pre_receive_hook_deployed():
    hook_path = "/home/user/sre-repo.git/hooks/pre-receive"
    assert os.path.isfile(hook_path), f"pre-receive hook missing at {hook_path}."
    assert os.access(hook_path, os.X_OK), f"pre-receive hook at {hook_path} is not executable."


def test_hook_source_makefile_and_deployed_binary():
    package_dir = "/app/git-sre-hook-1.0.0"
    source_path = os.path.join(package_dir, "main.go")
    makefile_path = os.path.join(package_dir, "Makefile")
    hook_path = "/home/user/sre-repo.git/hooks/pre-receive"

    assert os.path.isfile(source_path), "main.go is missing."
    assert os.path.isfile(makefile_path), "Makefile is missing."

    with open(source_path, "r") as f:
        source = f.read()
    assert re.search(r'os\.Getenv\(\s*"SSH_PORT"\s*\)', source), "main.go does not read SSH_PORT."
    assert "SSH_PRT" not in source, "main.go still references the misspelled SSH_PRT variable."

    with open(makefile_path, "r") as f:
        make_lines = f.read().splitlines()
    build_indexes = [i for i, line in enumerate(make_lines) if re.match(r"^build\s*:", line)]
    assert build_indexes, "Makefile has no build target."
    following = [line for line in make_lines[build_indexes[0] + 1:] if line.strip()]
    assert following and following[0].startswith("\t"), "The build target recipe must begin with a tab."

    with tempfile.TemporaryDirectory() as td:
        direct_binary = os.path.join(td, "hook")
        direct = subprocess.run(
            ["go", "build", "-o", direct_binary, source_path],
            cwd=package_dir, text=True, capture_output=True, timeout=60
        )
        assert direct.returncode == 0, f"main.go does not compile: {direct.stdout}{direct.stderr}"
        assert sha256(hook_path) == sha256(direct_binary), "Deployed pre-receive hook is not the compiled package artifact."

    built = subprocess.run(
        ["make", "-B", "build"], cwd=package_dir,
        text=True, capture_output=True, timeout=60
    )
    assert built.returncode == 0, f"Makefile build target failed: {built.stdout}{built.stderr}"
    package_hook = os.path.join(package_dir, "hook")
    assert os.path.isfile(package_hook), "Makefile build target did not produce hook."
    assert sha256(hook_path) == sha256(package_hook), "Deployed pre-receive hook differs from the Makefile-built hook."

    probe_port = str(20000 + secrets.randbelow(30000))
    env = os.environ.copy()
    env["SSH_PORT"] = probe_port
    env.pop("SSH_PRT", None)
    result = subprocess.run(
        [hook_path], input="", text=True, capture_output=True,
        env=env, timeout=10
    )
    assert result.returncode == 0, f"pre-receive hook failed when executed: {result.stdout}{result.stderr}"
    assert probe_port in result.stdout, "pre-receive hook did not use the SSH_PORT value when executed."


def test_ssh_tunnel_active():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.settimeout(2)
        result = s.connect_ex(("127.0.0.1", 9999))
        assert result == 0, "Port 9999 is not listening (SSH tunnel not active)."
        s.sendall(b"SSH-2.0-Test\r\n")
        response = s.recv(1024)
        assert b"SSH" in response, "Port 9999 is listening but does not appear to be an SSH tunnel."
    finally:
        s.close()


def test_port_9999_is_owned_by_requested_ssh_forwarder():
    listener_inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        if not os.path.exists(table):
            continue
        with open(table, "r") as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 10:
                    local_port = int(fields[1].rsplit(":", 1)[1], 16)
                    state = fields[3]
                    if local_port == 9999 and state == "0A":
                        listener_inodes.add(fields[9])
    assert listener_inodes, "No listening socket was found for port 9999."

    owner_pids = set()
    for pid in glob.glob("/proc/[0-9]*"):
        for fd in glob.glob(os.path.join(pid, "fd", "*")):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in listener_inodes:
                owner_pids.add(os.path.basename(pid))

    valid = False
    forward_re = re.compile(r"(?:[^:]+:)?9999:(?:localhost|127\.0\.0\.1):22$")
    for pid in owner_pids:
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                args = [x.decode(errors="replace") for x in f.read().split(b"\0") if x]
            executable = os.path.basename(os.readlink(f"/proc/{pid}/exe"))
        except OSError:
            continue
        if executable != "ssh":
            continue
        specs = []
        for i, arg in enumerate(args):
            if arg == "-L" and i + 1 < len(args):
                specs.append(args[i + 1])
            elif arg.startswith("-L") and len(arg) > 2:
                specs.append(arg[2:])
        if any(forward_re.fullmatch(spec) for spec in specs):
            valid = True
            break
    assert valid, "Port 9999 is not owned by an ssh process forwarding it to localhost:22."


def test_detector_binary_exists():
    binary_path = "/home/user/detector"
    assert os.path.isfile(binary_path), f"Detector binary missing at {binary_path}."
    assert os.access(binary_path, os.X_OK), f"Detector at {binary_path} is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Detector is not a compiled executable."
    info = subprocess.run(["go", "version", "-m", binary_path], text=True, capture_output=True, timeout=10)
    assert info.returncode == 0 and "go1" in info.stdout, "Detector does not contain Go build information."


def classify(binary, path):
    result = subprocess.run([binary, path], text=True, capture_output=True, timeout=10)
    assert result.returncode == 0, f"Detector errored on {os.path.basename(path)}: {result.stderr}"
    return result.stdout.strip()


def test_detector_adversarial_corpus():
    binary_path = "/home/user/detector"
    evil_dir = "/app/corpora/evil"
    clean_dir = "/app/corpora/clean"

    evil_files = glob.glob(os.path.join(evil_dir, "*"))
    clean_files = glob.glob(os.path.join(clean_dir, "*"))
    assert len(evil_files) > 0, "No files found in evil corpus."
    assert len(clean_files) > 0, "No files found in clean corpus."

    evil_failures = []
    for f in evil_files:
        try:
            if classify(binary_path, f) != "EVIL":
                evil_failures.append(os.path.basename(f))
        except Exception:
            evil_failures.append(f"{os.path.basename(f)} (crashed/errored)")

    clean_failures = []
    for f in clean_files:
        try:
            if classify(binary_path, f) != "CLEAN":
                clean_failures.append(os.path.basename(f))
        except Exception:
            clean_failures.append(f"{os.path.basename(f)} (crashed/errored)")

    error_messages = []
    if evil_failures:
        error_messages.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_messages.append(f"{len(clean_failures)} of {len(clean_files)} clean modified/flagged: {', '.join(clean_failures)}")
    assert not evil_failures and not clean_failures, " / ".join(error_messages)


def test_detector_runtime_generated_corpus_and_source():
    binary_path = "/home/user/detector"
    source_path = "/home/user/detector.go"
    assert os.path.isfile(source_path), "Detector Go source is missing."

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "detector-rebuilt")
        build = subprocess.run(
            ["go", "build", "-o", rebuilt, source_path],
            text=True, capture_output=True, timeout=60
        )
        assert build.returncode == 0, f"detector.go does not compile: {build.stdout}{build.stderr}"

        cases = []
        for i in range(8):
            token = secrets.token_hex(12)
            evil_text = (
                f"Sep 11 12:{i:02d}:01 host sshd[{1000+i}]: Connection from 198.51.100.{i+1}\n"
                f"Sep 11 12:{i:02d}:02 host sshd[{1000+i}]: Authentication refused: bad ownership or modes for "
                f"{'directory /home/user/.ssh' if i % 2 == 0 else 'file /home/user/.ssh/authorized_keys'}\n"
                f"audit marker {token}\n"
            )
            clean_lines = [
                f"sshd[{2000+i}]: Accepted publickey for user from 192.0.2.{i+1} port {30000+i} ssh2",
                f"sshd[{3000+i}]: Failed password for invalid user guest from 203.0.113.{i+1} port {40000+i} ssh2",
                f"sshd[{4000+i}]: Connection closed by authenticating user user 203.0.113.{i+1} port {50000+i} [preauth]",
            ]
            clean_text = clean_lines[i % len(clean_lines)] + f"\naudit marker {token}\n"
            for expected, text in (("EVIL", evil_text), ("CLEAN", clean_text)):
                path = os.path.join(td, secrets.token_hex(16) + ".log")
                with open(path, "w") as f:
                    f.write(text)
                cases.append((path, expected))

        for candidate in (binary_path, rebuilt):
            for path, expected in cases:
                actual = classify(candidate, path)
                assert actual == expected, f"{candidate} classified runtime-generated {os.path.basename(path)} as {actual}, expected {expected}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
