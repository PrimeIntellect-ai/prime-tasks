#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import shutil
import stat
import subprocess

SCRIPT_PATH = "/home/user/capacity_setup.sh"
OUTPUT_PATHS = [
    "/home/user/logrotate.conf",
    "/home/user/fstab_entry.txt",
    "/home/user/tunnel_cmd.txt",
]


def assert_regular_file(path):
    assert os.path.isfile(path), f"{path} does not exist."
    assert not os.path.islink(path), f"{path} must not be a symbolic link."
    assert stat.S_ISREG(os.lstat(path).st_mode), f"{path} is not a regular file."


def test_capacity_setup_script():
    """Verify and execute the setup script from a clean output state."""
    assert_regular_file(SCRIPT_PATH)
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable."

    for path in OUTPUT_PATHS:
        if os.path.lexists(path):
            if os.path.isdir(path) and not os.path.islink(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

    result = subprocess.run(
        ["runuser", "-u", "user", "--", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_logrotate_conf():
    """Verify a structurally valid logrotate block with the exact directives."""
    conf_path = "/home/user/logrotate.conf"
    assert_regular_file(conf_path)

    with open(conf_path, "r") as f:
        content = f.read()

    # Preserve the original content assertions.
    assert "/home/user/capacity_logs/usage.log" in content, "Logrotate conf missing target log file."
    assert "weekly" in content, "Logrotate conf missing 'weekly' directive."
    assert "rotate 4" in content, "Logrotate conf missing 'rotate 4' directive."
    assert "compress" in content, "Logrotate conf missing 'compress' directive."
    assert "missingok" in content, "Logrotate conf missing 'missingok' directive."

    uncommented = re.sub(r"(?m)#.*$", "", content).strip()
    match = re.fullmatch(
        r"/home/user/capacity_logs/usage\.log\s*\{(?P<body>.*?)\}",
        uncommented,
        flags=re.DOTALL,
    )
    assert match, "Logrotate configuration must be one properly formed block for the required log."

    directives = [line.strip() for line in match.group("body").splitlines() if line.strip()]
    assert len(directives) == 4, "Logrotate block must contain exactly the four required directives."
    assert directives.count("weekly") == 1, "Logrotate block must contain exactly one 'weekly' directive."
    assert directives.count("rotate 4") == 1, "Logrotate block must contain exactly one 'rotate 4' directive."
    assert directives.count("compress") == 1, "Logrotate block must contain exactly one 'compress' directive."
    assert directives.count("missingok") == 1, "Logrotate block must contain exactly one 'missingok' directive."


def test_fstab_entry():
    """Verify the generated file contains one standard, exact fstab entry."""
    fstab_path = "/home/user/fstab_entry.txt"
    assert_regular_file(fstab_path)

    with open(fstab_path, "r") as f:
        content = f.read().strip()

    lines = [line for line in content.splitlines() if line.strip() and not line.strip().startswith("#")]
    assert len(lines) >= 1, f"{fstab_path} is empty or contains no valid fstab entries."

    found = False
    for line in lines:
        parts = line.split()
        if len(parts) >= 6:
            if (parts[0] == "metrics-server:/var/log/metrics" and
                parts[1] == "/home/user/capacity_logs" and
                parts[2] == "nfs" and
                parts[3] == "ro,nosuid,nodev" and
                parts[4] == "0" and
                parts[5] == "0"):
                found = True
                break

    assert found, "Fstab entry does not match the required specification."
    assert len(lines) == 1, "The clean output file must contain exactly one active fstab entry."
    assert lines[0].split() == [
        "metrics-server:/var/log/metrics",
        "/home/user/capacity_logs",
        "nfs",
        "ro,nosuid,nodev",
        "0",
        "0",
    ], "The fstab entry must have exactly six correctly ordered fields."


def test_tunnel_cmd():
    """Parse and verify one exact, non-executed SSH tunneling command."""
    cmd_path = "/home/user/tunnel_cmd.txt"
    assert_regular_file(cmd_path)

    with open(cmd_path, "r") as f:
        content = f.read().strip()

    # Preserve the original content assertions.
    assert "ssh" in content, "Command does not contain 'ssh'."
    assert "9090:internal-api.local:80" in content, "Command missing the correct port forwarding string."
    assert "jump@gateway.corp.com" in content, "Command missing the correct bastion host."

    nonempty_lines = [line for line in content.splitlines() if line.strip()]
    assert len(nonempty_lines) == 1, "Tunnel file must contain a single command."

    try:
        tokens = shlex.split(nonempty_lines[0], posix=True)
    except ValueError as exc:
        raise AssertionError(f"Malformed shell command: {exc}")

    assert len(tokens) >= 4, "SSH command is incomplete."
    assert tokens[0] == "ssh", "The command must invoke ssh directly."
    assert tokens[-1] == "jump@gateway.corp.com", "The bastion host must be the SSH destination."

    flags = set()
    forward = None
    i = 1
    while i < len(tokens) - 1:
        token = tokens[i]
        assert token.startswith("-") and token != "-", f"Unexpected SSH argument: {token}"
        chars = token[1:]
        assert chars, "Malformed SSH option."
        j = 0
        while j < len(chars):
            option = chars[j]
            if option in ("f", "N"):
                flags.add(option)
                j += 1
            elif option == "L":
                assert forward is None, "The command must contain exactly one local forward."
                if j + 1 < len(chars):
                    forward = chars[j + 1:]
                else:
                    i += 1
                    assert i < len(tokens) - 1, "The -L option is missing its forwarding argument."
                    forward = tokens[i]
                j = len(chars)
            else:
                raise AssertionError(f"Unexpected SSH option '-{option}'.")
        i += 1

    assert "f" in flags, "Command missing '-f' flag."
    assert "N" in flags, "Command missing '-N' flag."
    assert forward == "9090:internal-api.local:80", "Local forwarding specification is incorrect."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
