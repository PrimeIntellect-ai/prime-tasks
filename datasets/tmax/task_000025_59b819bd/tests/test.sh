#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import shlex
import string
import subprocess
import pytest


def test_directories_and_links():
    assert os.path.isdir("/home/user/www/html"), "/home/user/www/html directory is missing."
    assert os.path.isdir("/home/user/nginx/conf"), "/home/user/nginx/conf directory is missing."

    sites_available = "/home/user/nginx/conf/sites-available/app.conf"
    sites_enabled = "/home/user/nginx/conf/sites-enabled/app.conf"

    assert os.path.isfile(sites_available), f"{sites_available} is missing."
    assert os.path.islink(sites_enabled), f"{sites_enabled} is not a symlink."

    target = os.readlink(sites_enabled)
    # Could be absolute or relative, resolve it
    resolved_target = os.path.normpath(os.path.join(os.path.dirname(sites_enabled), target))
    assert resolved_target == sites_available, f"Symlink {sites_enabled} does not point to {sites_available}."


def test_backup_and_config():
    original_file = "/home/user/nginx.conf.orig"
    backup_file = "/home/user/backup/nginx.conf.bak"
    assert os.path.isfile(backup_file), f"Backup file {backup_file} is missing."

    with open(backup_file, "r") as f:
        backup_content = f.read()
    assert "proxy_pass http://127.0.0.1:8080;" in backup_content, "Backup file does not match original content."

    with open(original_file, "rb") as f:
        original_bytes = f.read()
    with open(backup_file, "rb") as f:
        backup_bytes = f.read()
    assert backup_bytes == original_bytes, "Backup is not an exact copy of nginx.conf.orig."

    app_conf = "/home/user/nginx/conf/sites-available/app.conf"
    with open(app_conf, "r") as f:
        app_content = f.read()
    assert "proxy_pass http://127.0.0.1:9090;" in app_content, "app.conf does not contain the updated port 9090."
    assert "8080" not in app_content, "app.conf still contains the old port 8080."

    expected = original_bytes.replace(b"http://127.0.0.1:8080", b"http://127.0.0.1:9090")
    with open(app_conf, "rb") as f:
        app_bytes = f.read()
    assert app_bytes == expected, "app.conf must be a copy of the original with only the backend port updated."


def test_fake_fstab():
    fstab_file = "/home/user/fake_fstab"
    assert os.path.isfile(fstab_file), f"{fstab_file} is missing."

    with open(fstab_file, "r") as f:
        content = f.read()

    # Preserve the original component checks.
    assert "/home/user/data.img" in content
    assert "/home/user/www/html/data" in content
    assert "ext4" in content
    assert "defaults" in content

    valid_entry = False
    for raw_line in content.splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        fields = line.split()
        if len(fields) < 4:
            continue
        source, target, filesystem, options = fields[:4]
        option_set = set(options.split(","))
        if (source == "/home/user/data.img" and
                target == "/home/user/www/html/data" and
                filesystem == "ext4" and
                "defaults" in option_set):
            valid_entry = True
            break
    assert valid_entry, "fake_fstab does not contain a valid, uncommented mount entry."


def _top_level_commands(content):
    commands = []
    for raw_line in content.splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        current = []
        quote = None
        brace_depth = 0
        for char in raw_line:
            if quote:
                current.append(char)
                if char == quote:
                    quote = None
            elif char in ('\"', "'"):
                quote = char
                current.append(char)
            elif char == "{":
                brace_depth += 1
                current.append(char)
            elif char == "}":
                brace_depth = max(0, brace_depth - 1)
                current.append(char)
            elif char == ";" and brace_depth == 0:
                command = "".join(current).strip()
                if command:
                    commands.append(command)
                current = []
            else:
                current.append(char)
        command = "".join(current).strip()
        if command:
            commands.append(command)
    return commands


def _command_words(command):
    try:
        return shlex.split(command, posix=False)
    except ValueError:
        return []


def _tcl_value(word):
    if len(word) >= 2 and ((word[0] == word[-1] and word[0] in ('\"', "'")) or
                           (word[0] == "{" and word[-1] == "}")):
        return word[1:-1]
    return word


def test_expect_script():
    expect_script = "/home/user/test_backend.exp"
    assert os.path.isfile(expect_script), f"{expect_script} is missing."

    with open(expect_script, "r") as f:
        content = f.read()

    # Preserve the original checks.
    assert "spawn" in content, "Expect script missing 'spawn' command."
    assert "PING" in content, "Expect script missing 'PING' string."
    assert "PONG" in content, "Expect script missing 'PONG' string."

    commands = _top_level_commands(content)
    parsed = [_command_words(command) for command in commands]

    spawn_index = None
    for index, words in enumerate(parsed):
        if not words or words[0] != "spawn":
            continue
        args = words[1:]
        if args and args[0] == "--":
            args = args[1:]
        if args and _tcl_value(args[0]) == "/app/legacy_auth":
            spawn_index = index
            break
    assert spawn_index is not None, "Expect script does not actively spawn /app/legacy_auth."

    send_index = None
    for index in range(spawn_index + 1, len(parsed)):
        words = parsed[index]
        if not words or words[0] != "send":
            continue
        args = words[1:]
        if args and args[0] == "--":
            args = args[1:]
        if args:
            value = _tcl_value(args[0])
            if value in ("PING", "PING\\r", "PING\\n"):
                send_index = index
                break
    assert send_index is not None, "Expect script does not actively send PING after spawning the backend."

    pong_index = None
    for index in range(send_index + 1, len(parsed)):
        words = parsed[index]
        if words and words[0] == "expect" and len(words) >= 2:
            if _tcl_value(words[1]) == "PONG":
                pong_index = index
                break
    assert pong_index is not None, "Expect script does not actively expect PONG after sending PING."

    exits = [(index, words) for index, words in enumerate(parsed) if words and words[0] == "exit"]
    assert exits, "Expect script does not contain an exit command."
    first_exit_index, first_exit = exits[0]
    assert first_exit_index > pong_index, "Expect script exits before completing the PING/PONG exchange."
    assert len(first_exit) == 1 or _tcl_value(first_exit[1]) == "0", "Expect script must exit successfully."


def test_fuzz_equivalence():
    oracle = "/app/legacy_auth"
    agent = "/home/user/new_backend.py"

    assert os.path.isfile(oracle), f"Oracle {oracle} is missing."
    assert os.path.isfile(agent), f"Agent script {agent} is missing."
    assert os.access(agent, os.X_OK), f"Agent script {agent} is not executable."

    direct_input = "ExecutableCheck42"
    oracle_direct = subprocess.run([oracle, direct_input], capture_output=True, text=True)
    agent_direct = subprocess.run([agent, direct_input], capture_output=True, text=True)
    assert agent_direct.returncode == 0, f"Executable agent invocation failed: {agent_direct.stderr}"
    assert agent_direct.stdout == oracle_direct.stdout, "Direct executable invocation produced incorrect output."

    random.seed(42)
    chars = string.ascii_letters + string.digits

    for _ in range(500):
        length = random.randint(8, 64)
        fuzz_input = "".join(random.choice(chars) for _ in range(length))

        oracle_res = subprocess.run([oracle, fuzz_input], capture_output=True, text=True)
        agent_res = subprocess.run(["python3", agent, fuzz_input], capture_output=True, text=True)

        assert agent_res.returncode == 0, f"Agent script failed with return code {agent_res.returncode} on input '{fuzz_input}'\nStderr: {agent_res.stderr}"

        oracle_out = oracle_res.stdout
        agent_out = agent_res.stdout

        assert oracle_out == agent_out, f"Mismatch on input '{fuzz_input}'.\nOracle output: {repr(oracle_out)}\nAgent output: {repr(agent_out)}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
