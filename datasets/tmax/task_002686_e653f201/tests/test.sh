#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shlex
import stat
import subprocess
import sys

BASE = "/home/user/edge_package"


def shell_commands(path):
    commands = []
    with open(path, "r", encoding="utf-8") as f:
        for line_number, line in enumerate(f, 1):
            if line_number == 1 and line.startswith("#!"):
                continue
            lexer = shlex.shlex(line, posix=True, punctuation_chars=";&|<>()")
            lexer.whitespace_split = True
            lexer.commenters = "#"
            tokens = list(lexer)
            if not tokens:
                continue
            assert not any(token in {";", "&", "|", "&&", "||", "<", ">", "(", ")"} for token in tokens), \
                f"Unsupported shell control syntax in {path} on line {line_number}."
            commands.append(tokens)
    return commands


def test_directories_and_permissions():
    data_dir = f"{BASE}/data"
    keys_dir = f"{BASE}/keys"

    assert os.path.isdir(data_dir), f"Directory {data_dir} does not exist."
    assert os.path.isdir(keys_dir), f"Directory {keys_dir} does not exist."

    mode = stat.S_IMODE(os.stat(data_dir).st_mode)
    assert mode == 0o700, f"Permissions for {data_dir} are {oct(mode)}, expected 0o700."


def test_ssh_keys():
    priv_key = f"{BASE}/keys/iot_key"
    pub_key = f"{BASE}/keys/iot_key.pub"

    assert os.path.isfile(priv_key), f"Private key {priv_key} does not exist."
    assert os.path.isfile(pub_key), f"Public key {pub_key} does not exist."

    with open(priv_key, "r", encoding="utf-8") as f:
        content = f.read()
    assert "PRIVATE KEY" in content, "File does not appear to be a private key."

    derived = subprocess.run(
        ["ssh-keygen", "-y", "-f", priv_key],
        text=True,
        input="",
        capture_output=True,
        timeout=10,
    )
    assert derived.returncode == 0, f"iot_key is not a valid unencrypted SSH private key: {derived.stderr}"

    derived_fields = derived.stdout.strip().split()
    with open(pub_key, "r", encoding="utf-8") as f:
        public_fields = f.read().strip().split()
    assert len(derived_fields) >= 2 and len(public_fields) >= 2, "Malformed SSH public key."
    assert derived_fields[0] == "ssh-ed25519", "The private key is not ED25519."
    assert public_fields[0] == "ssh-ed25519", "The public key is not ED25519."
    assert derived_fields[:2] == public_fields[:2], "The public key does not match iot_key."


def test_network_setup_script():
    script = f"{BASE}/network_setup.sh"
    assert os.path.isfile(script), f"Script {script} does not exist."
    assert os.access(script, os.X_OK), f"Script {script} is not executable."

    with open(script, "r", encoding="utf-8") as f:
        content = f.read()

    assert "ip link add" in content and "sensor-net" in content and "dummy" in content, "network_setup.sh missing correct 'ip link add' command."
    assert "ip addr add 192.168.100.1/24" in content and "sensor-net" in content, "network_setup.sh missing correct 'ip addr add' command."

    commands = shell_commands(script)
    assert commands == [
        ["ip", "link", "add", "sensor-net", "type", "dummy"],
        ["ip", "addr", "add", "192.168.100.1/24", "dev", "sensor-net"],
    ], f"network_setup.sh must contain exactly the two required ip commands; got {commands!r}."


def test_tunnel_script():
    script = f"{BASE}/tunnel.sh"
    assert os.path.isfile(script), f"Script {script} does not exist."
    assert os.access(script, os.X_OK), f"Script {script} is not executable."

    with open(script, "r", encoding="utf-8") as f:
        content = f.read()

    assert "ssh " in content, "tunnel.sh missing ssh command."
    assert "-f" in content, "tunnel.sh missing -f flag."
    assert "-N" in content, "tunnel.sh missing -N flag."
    assert "-L" in content, "tunnel.sh missing -L flag."
    assert "8080" in content, "tunnel.sh missing local port 8080."
    assert "9000" in content, "tunnel.sh missing remote port 9000."
    assert "192.168.100.5" in content, "tunnel.sh missing target IP 192.168.100.5."
    assert "sensor_user" in content, "tunnel.sh missing user sensor_user."
    assert f"{BASE}/keys/iot_key" in content, "tunnel.sh missing correct SSH key path."

    commands = shell_commands(script)
    assert len(commands) == 1 and commands[0] and commands[0][0] == "ssh", \
        f"tunnel.sh must contain exactly one ssh command; got {commands!r}."

    args = commands[0][1:]
    background = False
    no_command = False
    identity = None
    forwarding = None
    destination = None
    i = 0
    while i < len(args):
        arg = args[i]
        if arg in ("-f", "-N"):
            if arg == "-f":
                assert not background, "Duplicate -f option."
                background = True
            else:
                assert not no_command, "Duplicate -N option."
                no_command = True
        elif arg in ("-fN", "-Nf"):
            assert not background and not no_command, "Duplicate -f or -N option."
            background = True
            no_command = True
        elif arg == "-i":
            assert identity is None and i + 1 < len(args), "Invalid -i option."
            i += 1
            identity = args[i]
        elif arg.startswith("-i") and len(arg) > 2:
            assert identity is None, "Duplicate -i option."
            identity = arg[2:]
        elif arg == "-L":
            assert forwarding is None and i + 1 < len(args), "Invalid -L option."
            i += 1
            forwarding = args[i]
        elif arg.startswith("-L") and len(arg) > 2:
            assert forwarding is None, "Duplicate -L option."
            forwarding = arg[2:]
        elif not arg.startswith("-") and destination is None:
            destination = arg
        else:
            raise AssertionError(f"Unexpected ssh argument: {arg!r}")
        i += 1

    assert background and no_command, "ssh command must use background and no-command flags."
    assert identity == f"{BASE}/keys/iot_key", "ssh command uses the wrong identity file."
    assert forwarding == "8080:192.168.100.5:9000", "ssh command has the wrong local forwarding specification."
    assert destination == "sensor_user@192.168.100.5", "ssh command has the wrong SSH destination."


def run_verifier_script(script, payload):
    proc = subprocess.run(
        [script], input=json.dumps(payload), text=True, capture_output=True, timeout=10
    )
    assert proc.returncode == 0, f"verify_data.py failed to run. Stderr: {proc.stderr}"
    return proc.stdout.strip()


def test_verify_data_script():
    script = f"{BASE}/verify_data.py"
    assert os.path.isfile(script), f"Script {script} does not exist."
    assert os.access(script, os.X_OK), f"Script {script} is not executable."

    with open(script, "r", encoding="utf-8") as f:
        first_line = f.readline()
    assert first_line.startswith("#!") and "python3" in first_line, "verify_data.py must be an executable Python 3 script."

    # Preserve the original fixed checks.
    assert run_verifier_script(script, {"status": "active"}) == "active"
    assert run_verifier_script(script, {"data": "none"}) == "unknown"

    # Exercise unpredictable inputs and non-string JSON values.
    random_statuses = [
        secrets.token_hex(19),
        f"state-{secrets.token_urlsafe(23)}",
        secrets.randbelow(2_000_000_000) - 1_000_000_000,
        [secrets.token_hex(5), secrets.randbelow(100000)],
        {"code": secrets.randbelow(10000), "name": secrets.token_hex(6)},
    ]
    for value in random_statuses:
        payload = {
            "nonce": secrets.token_hex(20),
            "status": value,
            "other": [secrets.token_hex(4), secrets.randbelow(1000)],
        }
        expected = str(value)
        assert run_verifier_script(script, payload) == expected, f"Expected {expected!r}."

    for _ in range(4):
        payload = {secrets.token_hex(8): secrets.token_urlsafe(12)}
        assert "status" not in payload
        assert run_verifier_script(script, payload) == "unknown"

    # Confirm the file is Python rather than an executable of another language.
    syntax = subprocess.run(
        [sys.executable, "-m", "py_compile", script], text=True, capture_output=True, timeout=10
    )
    assert syntax.returncode == 0, f"verify_data.py is not valid Python 3: {syntax.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
