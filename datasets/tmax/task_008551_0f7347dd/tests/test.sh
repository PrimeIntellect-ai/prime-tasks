#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import shlex
import stat
import subprocess
import tempfile


def test_phase1_suid_hashes():
    output_file = "/home/user/suid_hashes.txt"
    assert os.path.isfile(output_file), f"Phase 1 output file {output_file} is missing."

    bin_dir = "/home/user/fs_dump/bin"
    expected_lines = []

    # Find SUID files and compute hashes dynamically
    for root, _, files in os.walk(bin_dir):
        for file in files:
            filepath = os.path.join(root, file)
            st = os.stat(filepath)
            if st.st_mode & stat.S_ISUID:
                with open(filepath, "rb") as f:
                    file_hash = hashlib.sha256(f.read()).hexdigest()
                expected_lines.append(f"{file_hash}  {filepath}")

    expected_lines.sort()

    with open(output_file, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, "The SUID hashes file does not match the expected output or is not sorted correctly."


def test_phase2_redacted_environ():
    redacted_file = "/home/user/evidence/redacted_environ.txt"
    assert os.path.isfile(redacted_file), f"Phase 2 output file {redacted_file} is missing."

    expected_content = (
        "USER=admin\n"
        "PATH=/usr/bin:/bin\n"
        "PASSWORD=REDACTED\n"
        "HOME=/home/admin\n"
    )

    with open(redacted_file, "r") as f:
        actual_content = f.read()

    assert actual_content == expected_content, f"Content of {redacted_file} is incorrect."


def test_phase2_hash_file():
    hash_file = "/home/user/evidence/hash.txt"
    redacted_file = "/home/user/evidence/redacted_environ.txt"

    assert os.path.isfile(hash_file), f"Phase 2 hash file {hash_file} is missing."
    assert os.path.isfile(redacted_file), f"Phase 2 redacted file {redacted_file} is missing."

    with open(redacted_file, "rb") as f:
        expected_hash = hashlib.sha256(f.read()).hexdigest()

    with open(hash_file, "r") as f:
        actual_hash = f.read().strip()

    assert actual_hash == expected_hash, f"The hash in {hash_file} does not match the SHA-256 of {redacted_file}."


def test_phase2_c_program():
    c_source = "/home/user/evidence/extractor.c"
    c_binary = "/home/user/evidence/extractor"

    assert os.path.isfile(c_source), f"C source file {c_source} is missing."
    assert os.path.isfile(c_binary), f"Compiled binary {c_binary} is missing."

    st = os.stat(c_binary)
    assert st.st_mode & stat.S_IXUSR, f"The compiled binary {c_binary} is not executable."

    with open(c_binary, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{c_binary} is not a compiled executable."

    environ_file = "/home/user/evidence/environ.txt"
    redacted_file = "/home/user/evidence/redacted_environ.txt"
    hash_file = "/home/user/evidence/hash.txt"

    with open(environ_file, "rb") as f:
        original_environ = f.read()
    with open(redacted_file, "rb") as f:
        original_redacted = f.read()
    with open(hash_file, "rb") as f:
        original_hash = f.read()

    token = os.urandom(18).hex().encode("ascii")
    cases = [
        (
            b"FIRST=" + token + b"\nPASSWORD=" + token[::-1] +
            b"\nPASSWORDX=keep-" + token + b"\n PASSWORD=keep-too\nLAST=end\n",
            b"FIRST=" + token + b"\nPASSWORD=REDACTED\nPASSWORDX=keep-" +
            token + b"\n PASSWORD=keep-too\nLAST=end\n",
        ),
        (
            b"PASSWORD=one\nMIDDLE=" + token + b"\nPASSWORD=two",
            b"PASSWORD=REDACTED\nMIDDLE=" + token + b"\nPASSWORD=REDACTED\n",
        ),
        (
            b"NO_SECRET=" + token,
            b"NO_SECRET=" + token,
        ),
    ]

    def verify_program(program, input_bytes):
        with open(environ_file, "wb") as f:
            f.write(input_bytes)
        for path in (redacted_file, hash_file):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass

        result = subprocess.run([program], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
        assert result.returncode == 0, (
            f"{program} failed when processing a test environment: "
            f"{result.stderr.decode(errors='replace')}"
        )
        assert os.path.isfile(redacted_file), f"{program} did not create redacted_environ.txt."
        assert os.path.isfile(hash_file), f"{program} did not create hash.txt."

    try:
        with tempfile.TemporaryDirectory() as td:
            rebuilt = os.path.join(td, "extractor")
            build = subprocess.run(
                ["gcc", c_source, "-o", rebuilt, "-lcrypto"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
            )
            assert build.returncode == 0, (
                "extractor.c does not compile with libcrypto: "
                + build.stderr.decode(errors="replace")
            )

            with open(rebuilt, "rb") as f:
                assert f.read(4) == b"\x7fELF", "Compiling extractor.c did not produce an ELF executable."

            dynamic_info = subprocess.run(
                ["readelf", "-d", rebuilt],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert dynamic_info.returncode == 0, "Could not inspect the rebuilt executable."
            assert re.search(r"libcrypto\.so", dynamic_info.stdout), (
                "The rebuilt C program is not linked to the OpenSSL crypto library."
            )

            for program in (c_binary, rebuilt):
                for input_bytes, expected_bytes in cases:
                    verify_program(program, input_bytes)
                    with open(redacted_file, "rb") as f:
                        actual_bytes = f.read()
                    assert actual_bytes == expected_bytes, (
                        f"{program} did not redact exactly the lines beginning with PASSWORD=."
                    )
                    with open(hash_file, "rb") as f:
                        actual_hash = f.read().strip()
                    expected_hash = hashlib.sha256(expected_bytes).hexdigest().encode("ascii")
                    assert re.fullmatch(rb"[0-9a-f]{64}", actual_hash), (
                        f"{program} did not write a lowercase SHA-256 hex string."
                    )
                    assert actual_hash == expected_hash, (
                        f"{program} wrote an incorrect hash for its redacted output."
                    )
    finally:
        with open(environ_file, "wb") as f:
            f.write(original_environ)
        with open(redacted_file, "wb") as f:
            f.write(original_redacted)
        with open(hash_file, "wb") as f:
            f.write(original_hash)


def test_phase3_iptables_script():
    script_file = "/home/user/iptables_rule.sh"
    assert os.path.isfile(script_file), f"Phase 3 script {script_file} is missing."

    st = os.stat(script_file)
    assert st.st_mode & stat.S_IXUSR, f"The script {script_file} is not executable."

    with open(script_file, "r") as f:
        lines = f.readlines()

    iptables_commands = [line.strip() for line in lines if line.strip() and not line.strip().startswith("#")]

    assert len(iptables_commands) == 1, "The script must contain exactly one uncommented command."

    cmd = iptables_commands[0]

    # Preserve the original required-component assertions.
    assert cmd.startswith("iptables"), "The command must start with 'iptables'."
    assert "-A INPUT" in cmd or "-I INPUT" in cmd, "The command must append or insert to the INPUT chain."
    assert "10.10.10.55" in cmd, "The command must target the IP 10.10.10.55."
    assert "1337" in cmd, "The command must target port 1337."
    assert "-j DROP" in cmd, "The command must jump to the DROP target."
    assert "-p tcp" in cmd or "--protocol tcp" in cmd, "The command must specify the TCP protocol."

    syntax = subprocess.run(["bash", "-n", script_file], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert syntax.returncode == 0, "The iptables script is not valid bash syntax."

    with open("/home/user/evidence/syslog", "r") as f:
        syslog = f.read()
    matches = re.findall(r"backdoor port\s+1337\s+from\s+([0-9]+(?:\.[0-9]+){3})", syslog)
    assert len(matches) == 1, "Could not uniquely identify the backdoor source IP in syslog."
    expected_ip = matches[0]

    tokens = shlex.split(cmd, comments=False, posix=True)
    assert tokens and tokens[0] == "iptables", "The command must invoke iptables directly."

    found = set()
    i = 1
    while i < len(tokens):
        token = tokens[i]
        if token in ("-A", "-I", "-p", "--protocol", "-s", "--source", "--dport", "--destination-port", "-j", "--jump", "-m"):
            assert i + 1 < len(tokens), f"Missing argument for {token}."
            value = tokens[i + 1]
            i += 2
            if token in ("-A", "-I"):
                assert value == "INPUT" and "chain" not in found, "The rule must target INPUT exactly once."
                found.add("chain")
            elif token in ("-p", "--protocol"):
                assert value.lower() == "tcp" and "protocol" not in found, "The rule protocol must be TCP."
                found.add("protocol")
            elif token in ("-s", "--source"):
                assert value == expected_ip and "source" not in found, "The rule has the wrong source IP."
                found.add("source")
            elif token in ("--dport", "--destination-port"):
                assert value == "1337" and "port" not in found, "The rule has the wrong destination port."
                found.add("port")
            elif token in ("-j", "--jump"):
                assert value == "DROP" and "jump" not in found, "The rule must jump to DROP."
                found.add("jump")
            else:
                assert value.lower() == "tcp", "Only the TCP match module is appropriate here."
        elif token.startswith("--") and "=" in token:
            option, value = token.split("=", 1)
            mapping = {
                "--protocol": ("protocol", "tcp"),
                "--source": ("source", expected_ip),
                "--dport": ("port", "1337"),
                "--destination-port": ("port", "1337"),
                "--jump": ("jump", "DROP"),
            }
            assert option in mapping, f"Unexpected iptables option: {option}"
            key, expected = mapping[option]
            assert value == expected and key not in found, f"Invalid or duplicate {option} option."
            found.add(key)
            i += 1
        else:
            raise AssertionError(f"Unexpected token in iptables command: {token}")

    assert found == {"chain", "protocol", "source", "port", "jump"}, (
        "The command must contain exactly an INPUT chain action, TCP protocol, source IP, "
        "destination port 1337, and DROP target."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
