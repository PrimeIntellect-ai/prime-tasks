#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import subprocess
import sys

from scapy.all import IP, TCP, Raw, rdpcap


def incident_details():
    packets = rdpcap("/home/user/capture.pcap")
    candidates = [
        p for p in packets
        if p.haslayer(IP) and p.haslayer(TCP) and p.haslayer(Raw)
        and int(p[TCP].dport) == 7777
    ]
    assert candidates, "No attacker TCP payload to port 7777 found in capture."

    packet = candidates[0]
    encoded = bytes(packet[Raw].load)
    known_command = b"whoami"
    assert len(encoded) == len(known_command), "Unexpected incident payload length."

    keys = {
        encoded[i] ^ known_command[i]
        for i in range(len(known_command))
    }
    assert len(keys) == 1, "Incident payload is not a single-byte XOR encoding of whoami."
    key = keys.pop()
    assert bytes(b ^ key for b in encoded) == known_command
    return packet[IP].src, key


def test_attacker_ip():
    """Verify that the attacker IP was correctly identified."""
    ip_file = "/home/user/attacker_ip.txt"
    assert os.path.isfile(ip_file), f"Missing file: {ip_file}"

    with open(ip_file, "r") as f:
        ip = f.read().strip()

    assert ip == "10.13.37.100", f"Incorrect attacker IP in {ip_file}. Found: {ip}"
    captured_ip, _ = incident_details()
    assert ip == captured_ip, "Attacker IP does not match the client sending data to port 7777."


def test_craft_exploit_script_generates_payload():
    """Execute the requested Python artifact and verify that it creates the payload."""
    script_file = "/home/user/craft_exploit.py"
    assert os.path.isfile(script_file), f"Missing file: {script_file}"
    assert not os.path.islink(script_file), f"{script_file} must be a Python script, not a symlink."

    with open(script_file, "rb") as f:
        source = f.read()
    compile(source, script_file, "exec")

    payload_file = "/home/user/new_payload.bin"
    if os.path.lexists(payload_file):
        os.unlink(payload_file)

    result = subprocess.run(
        [sys.executable, script_file],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"craft_exploit.py failed with exit code {result.returncode}: "
        f"{result.stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(payload_file), "craft_exploit.py did not create /home/user/new_payload.bin."

    with open(payload_file, "rb") as f:
        payload = f.read()
    _, key = incident_details()
    assert payload == bytes(b ^ key for b in b"cat /etc/passwd"), (
        "craft_exploit.py did not generate the payload using the XOR key from the capture."
    )


def test_new_payload():
    """Verify that the new payload was correctly crafted using the discovered XOR key."""
    payload_file = "/home/user/new_payload.bin"
    assert os.path.isfile(payload_file), f"Missing file: {payload_file}"

    with open(payload_file, "rb") as f:
        payload = f.read()

    expected_command = "cat /etc/passwd"
    expected_payload = bytes([ord(c) ^ 0x55 for c in expected_command])

    assert payload == expected_payload, f"Payload in {payload_file} does not match the expected XOR'd bytes."


def test_block_attacker_script():
    """Verify the firewall script contains one real, correct iptables command."""
    script_file = "/home/user/block_attacker.sh"
    assert os.path.isfile(script_file), f"Missing file: {script_file}"
    assert not os.path.islink(script_file), f"{script_file} must be a script, not a symlink."

    with open(script_file, "r") as f:
        content = f.read().strip()

    # Preserve the original required checks.
    assert "iptables" in content, "iptables command not found in script."
    assert "-A INPUT" in content or "--append INPUT" in content, "Rule must be appended to the INPUT chain."
    assert "-p tcp" in content or "--protocol tcp" in content, "Rule must specify TCP protocol."
    assert "-s 10.13.37.100" in content or "--source 10.13.37.100" in content, "Rule must specify the attacker's source IP."
    assert "--dport 7777" in content or "--destination-port 7777" in content, "Rule must specify destination port 7777."
    assert "-j DROP" in content or "--jump DROP" in content, "Rule must DROP the traffic."
    assert "sudo" not in content, "Script must not use sudo."

    syntax = subprocess.run(["bash", "-n", script_file], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert syntax.returncode == 0, f"Firewall script has invalid shell syntax: {syntax.stderr.decode(errors='replace')}"

    commands = []
    for raw_line in content.splitlines():
        stripped = raw_line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        lexer = shlex.shlex(raw_line, posix=True, punctuation_chars=";&|<>()")
        lexer.whitespace_split = True
        lexer.commenters = "#"
        words = list(lexer)
        if words:
            commands.append(words)

    assert len(commands) == 1, "Firewall script must contain exactly one active command."
    words = commands[0]
    assert os.path.basename(words[0]) == "iptables", "The active command must invoke iptables directly."
    assert not any(token in {";", "&&", "||", "|", "&", "<", ">", "(", ")"} for token in words), (
        "Shell control operators are not allowed in the firewall command."
    )

    expected = {
        "chain": ({"-A", "--append"}, "INPUT"),
        "protocol": ({"-p", "--protocol"}, "tcp"),
        "source": ({"-s", "--source"}, "10.13.37.100"),
        "port": ({"--dport", "--destination-port"}, "7777"),
        "target": ({"-j", "--jump"}, "DROP"),
    }
    found = set()
    i = 1
    while i < len(words):
        if i + 1 >= len(words):
            raise AssertionError(f"Incomplete iptables option: {words[i]}")
        option, value = words[i], words[i + 1]
        if option == "-m" and value == "tcp":
            i += 2
            continue
        matches = [name for name, (aliases, required) in expected.items() if option in aliases and value == required]
        assert len(matches) == 1, f"Unexpected or incorrect iptables arguments: {option} {value}"
        assert matches[0] not in found, f"Duplicate iptables setting: {option}"
        found.add(matches[0])
        i += 2
    assert found == set(expected), "The active iptables command is missing required arguments."


def test_ssh_key_generated():
    """Verify that a real, unencrypted Ed25519 SSH key pair was generated."""
    key_file = "/home/user/admin_key"
    public_file = "/home/user/admin_key.pub"
    assert os.path.isfile(key_file), f"Missing file: {key_file}"
    assert not os.path.islink(key_file), f"{key_file} must be a private-key file, not a symlink."

    with open(key_file, "r") as f:
        content = f.read()

    assert "BEGIN OPENSSH PRIVATE KEY" in content, f"{key_file} does not appear to be a valid OpenSSH private key."

    derived = subprocess.run(
        ["ssh-keygen", "-y", "-P", "", "-f", key_file],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert derived.returncode == 0, (
        "admin_key is not a valid unencrypted OpenSSH private key: "
        + derived.stderr.decode(errors="replace")
    )
    derived_fields = derived.stdout.decode().strip().split()
    assert len(derived_fields) >= 2 and derived_fields[0] == "ssh-ed25519", "admin_key must be an Ed25519 key."

    assert os.path.isfile(public_file), f"Missing public key: {public_file}"
    with open(public_file, "r") as f:
        public_fields = f.read().strip().split()
    assert len(public_fields) >= 2, f"Invalid public key: {public_file}"
    assert public_fields[:2] == derived_fields[:2], "admin_key.pub does not match admin_key."


def test_hardened_sshd_config():
    """Verify the hardened SSH configuration contains effective required settings."""
    config_file = "/home/user/hardened_sshd_config"
    assert os.path.isfile(config_file), f"Missing file: {config_file}"

    with open(config_file, "r") as f:
        lines = f.readlines()

    # Preserve the original checks.
    active_settings = {}
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = re.split(r'\s+', line, maxsplit=1)
        if len(parts) == 2:
            active_settings[parts[0].lower()] = parts[1].lower()

    assert active_settings.get("passwordauthentication") == "no", "PasswordAuthentication must be set to 'no'."
    assert active_settings.get("permitrootlogin") == "no", "PermitRootLogin must be set to 'no'."
    assert active_settings.get("x11forwarding") == "no", "X11Forwarding must be set to 'no'."
    assert active_settings.get("protocol") == "2", "Protocol must be explicitly set to '2'."

    # sshd uses the first obtained value; settings after a Match block are not global.
    effective_global = {}
    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        parts = re.split(r'\s+', line, maxsplit=1)
        if parts[0].lower() == "match":
            break
        if len(parts) == 2:
            effective_global.setdefault(parts[0].lower(), parts[1].lower())

    assert effective_global.get("passwordauthentication") == "no", "Effective global PasswordAuthentication must be 'no'."
    assert effective_global.get("permitrootlogin") == "no", "Effective global PermitRootLogin must be 'no'."
    assert effective_global.get("x11forwarding") == "no", "Effective global X11Forwarding must be 'no'."
    assert effective_global.get("protocol") == "2", "Effective global Protocol must be '2'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
