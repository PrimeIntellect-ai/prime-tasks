#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shlex
import stat
import subprocess
import tempfile


def extract_evidence_values():
    with open("/home/user/evidence/stealer.bin", "rb") as f:
        binary = f.read()

    ip_match = re.search(rb"EXFIL_IP:((?:[0-9]{1,3}\\.){3}[0-9]{1,3})", binary)
    key_match = re.search(rb"XOR_KEY:0x([0-9A-Fa-f]{2})", binary)
    assert ip_match is not None, "Could not derive the exfiltration IP from stealer.bin."
    assert key_match is not None, "Could not derive the XOR key from stealer.bin."
    return ip_match.group(1).decode("ascii"), int(key_match.group(1), 16)


def test_decoder_cpp_exists():
    assert os.path.isfile("/home/user/decoder.cpp"), "The C++ program /home/user/decoder.cpp is missing."


def test_decoder_compiles_and_decrypts_inputs():
    source = "/home/user/decoder.cpp"
    decoder = "/home/user/decoder"
    recovered = "/home/user/recovered.txt"
    assert os.path.isfile(source), "The C++ program /home/user/decoder.cpp is missing."

    if os.path.exists(decoder):
        os.remove(decoder)
    compile_result = subprocess.run(
        ["g++", source, "-o", decoder],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_result.returncode == 0, "decoder.cpp did not compile successfully with g++."
    assert os.path.isfile(decoder), "Compiling decoder.cpp did not produce /home/user/decoder."

    no_arg = subprocess.run([decoder], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert no_arg.returncode != 0, "The decoder must reject invocation without an input path."

    two_args = subprocess.run(
        [decoder, "/home/user/evidence/payload.enc", "/home/user/evidence/payload.enc"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert two_args.returncode != 0, "The decoder must reject invocation with more than one argument."

    _, key = extract_evidence_values()
    probe_plaintext = os.urandom(37)
    probe_ciphertext = bytes(value ^ key for value in probe_plaintext)
    with tempfile.NamedTemporaryFile(prefix="decoder_probe_", delete=False) as probe:
        probe.write(probe_ciphertext)
        probe_path = probe.name

    try:
        if os.path.exists(recovered):
            os.remove(recovered)
        probe_result = subprocess.run([decoder, probe_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        assert probe_result.returncode == 0, "The decoder failed when given a valid encrypted input file."
        assert os.path.isfile(recovered), "The decoder did not create /home/user/recovered.txt."
        with open(recovered, "rb") as f:
            assert f.read() == probe_plaintext, "The decoder did not correctly XOR-decrypt a verifier-generated input."
    finally:
        os.unlink(probe_path)

    with open("/home/user/evidence/payload.enc", "rb") as f:
        encrypted_payload = f.read()
    expected_payload = bytes(value ^ key for value in encrypted_payload)
    if os.path.exists(recovered):
        os.remove(recovered)
    payload_result = subprocess.run(
        [decoder, "/home/user/evidence/payload.enc"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert payload_result.returncode == 0, "The decoder failed on /home/user/evidence/payload.enc."
    assert os.path.isfile(recovered), "The decoder did not create /home/user/recovered.txt for the evidence payload."
    with open(recovered, "rb") as f:
        assert f.read() == expected_payload, "The evidence payload was not decrypted byte-for-byte with the extracted XOR key."


def test_recovered_txt():
    recovered_path = "/home/user/recovered.txt"
    assert os.path.isfile(recovered_path), f"The file {recovered_path} is missing."
    with open(recovered_path, "r") as f:
        content = f.read().strip()
    assert content == "root_db_pass:Sup3rS3cr3t!99", "The decrypted content in recovered.txt is incorrect."


def test_block_ip_script():
    script_path = "/home/user/block_ip.sh"
    assert os.path.isfile(script_path), f"The script {script_path} is missing."
    with open(script_path, "r") as f:
        content = f.read()

    match = re.search(r'iptables\s+-A\s+OUTPUT\s+-d\s+198\.51\.100\.77\s+-j\s+DROP', content)
    assert match is not None, "The block_ip.sh script does not contain the correct iptables command to drop traffic to 198.51.100.77."

    syntax = subprocess.run(["bash", "-n", script_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
    assert syntax.returncode == 0, "The block_ip.sh script is not valid bash syntax."

    expected_ip, _ = extract_evidence_values()
    command_lines = []
    for line_number, line in enumerate(content.splitlines()):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        try:
            tokens = shlex.split(line, comments=True, posix=True)
        except ValueError as exc:
            raise AssertionError(f"Invalid shell command on line {line_number + 1}: {exc}")
        if tokens:
            command_lines.append(tokens)

    assert len(command_lines) == 1, "block_ip.sh must contain exactly one executable command."
    tokens = command_lines[0]
    if tokens and tokens[0] == "sudo":
        tokens = tokens[1:]
    assert len(tokens) == 7, "The sole command in block_ip.sh must be exactly the required iptables rule."
    assert os.path.basename(tokens[0]) == "iptables", "The executable command in block_ip.sh must invoke iptables."
    assert tokens[1:] == ["-A", "OUTPUT", "-d", expected_ip, "-j", "DROP"], "The iptables command must append exactly the required OUTPUT DROP rule."


def test_authorized_keys_content():
    auth_keys_path = "/home/user/.ssh/authorized_keys"
    assert os.path.isfile(auth_keys_path), f"The file {auth_keys_path} is missing."
    with open(auth_keys_path, "r") as f:
        content = f.read()

    assert "attacker@exfil-server" not in content, "The attacker's SSH key was not removed from authorized_keys."
    assert "user@legitimate-machine" in content, "A legitimate SSH key (user@legitimate-machine) was incorrectly removed."
    assert "admin@jumpbox" in content, "A legitimate SSH key (admin@jumpbox) was incorrectly removed."


def test_authorized_keys_permissions():
    auth_keys_path = "/home/user/.ssh/authorized_keys"
    assert os.path.isfile(auth_keys_path), f"The file {auth_keys_path} is missing."

    st = os.stat(auth_keys_path)
    permissions = stat.S_IMODE(st.st_mode)

    assert permissions == 0o600, f"The permissions of {auth_keys_path} are incorrect. Expected 600, got {oct(permissions)}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
