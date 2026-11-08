#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import hmac
import os
import pwd
import secrets
import stat
import struct
import subprocess

ORACLE_PATH = "/app/oracle_bin"
AGENT_SCRIPT = "/home/user/redirect_handler.py"
SECRET_KEY = b"5938210476"

rng = secrets.SystemRandom()


def generate_random_hex(length):
    return os.urandom(length).hex()


def generate_token(url, key=SECRET_KEY, corrupt_magic=False, corrupt_length=False, corrupt_hmac=False):
    magic = b"REDI" if not corrupt_magic else b"R3DI"
    url_bytes = url.encode("ascii", errors="ignore")
    length = len(url_bytes)
    length_field = struct.pack(">H", (length + 1) % 65536 if corrupt_length else length)
    data = magic + length_field + url_bytes
    sig = hmac.new(key, data, hashlib.sha256).digest()
    if corrupt_hmac:
        sig = bytes([sig[0] ^ 0xFF]) + sig[1:]
    return (data + sig).hex()


def generate_inputs(n=2000):
    inputs = []
    for _ in range(n // 5):
        inputs.append(generate_random_hex(rng.randint(0, 150)))

        url = "https://example.com/" + "".join(chr(rng.randint(32, 126)) for _ in range(rng.randint(5, 20)))
        inputs.append(generate_token(url, corrupt_length=True))

        url = "https://secure.internal/" + "".join(chr(rng.randint(97, 122)) for _ in range(rng.randint(5, 20)))
        inputs.append(generate_token(url, corrupt_hmac=True))

        bad_urls = [
            "http://secure.internal/admin",
            "https://secure.internal/admin?user=1",
            "https://secure.internal/admin@domain",
            "https://secure.internal/admin//dashboard",
            "https://attacker.com/",
        ]
        inputs.append(generate_token(rng.choice(bad_urls)))

        url = "https://secure.internal/" + "".join(chr(rng.randint(97, 122)) for _ in range(rng.randint(5, 20)))
        inputs.append(generate_token(url))
    return inputs


def expected_output(hex_input):
    try:
        data = bytes.fromhex(hex_input)
    except ValueError:
        return "FORMAT_ERROR"

    if len(data) < 38 or data[:4] != b"REDI":
        return "FORMAT_ERROR"

    url_len = int.from_bytes(data[4:6], "big")
    if len(data) != 6 + url_len + 32:
        return "FORMAT_ERROR"

    body, supplied_mac = data[:-32], data[-32:]
    calculated_mac = hmac.new(SECRET_KEY, body, hashlib.sha256).digest()
    if not hmac.compare_digest(calculated_mac, supplied_mac):
        return "INVALID_SIG"

    url_bytes = data[6:-32]
    if any(b > 127 for b in url_bytes):
        return "FORMAT_ERROR"
    url = url_bytes.decode("ascii")

    if not url.startswith("https://secure.internal/"):
        return "INVALID_URL"
    if "@" in url or "?" in url or "//" in url[8:]:
        return "INVALID_URL"
    return "ALLOW: " + url


def remove_executable_helpers():
    roots = ["/app", "/home/user", "/tmp", "/var/tmp", "/dev/shm"]
    for root in roots:
        if not os.path.isdir(root):
            continue
        for directory, _, files in os.walk(root):
            for name in files:
                path = os.path.join(directory, name)
                if path == AGENT_SCRIPT:
                    continue
                try:
                    with open(path, "rb") as f:
                        is_elf = f.read(4) == b"\x7fELF"
                    if is_elf:
                        os.unlink(path)
                except (OSError, PermissionError):
                    pass


def lock_writable_staging_areas():
    saved = []
    roots = ["/app", "/home/user", "/tmp", "/var/tmp", "/dev/shm"]
    for root in roots:
        if not os.path.exists(root):
            continue
        for directory, dirs, files in os.walk(root):
            for path in [directory] + [os.path.join(directory, n) for n in files]:
                try:
                    mode = stat.S_IMODE(os.lstat(path).st_mode)
                    saved.append((path, mode))
                    os.chmod(path, mode & ~0o222)
                except OSError:
                    pass
    return saved


def restore_modes(saved):
    for path, mode in reversed(saved):
        try:
            os.chmod(path, mode)
        except OSError:
            pass


def run_as_user(command):
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return subprocess.run(
        command,
        cwd="/",
        env={"PATH": "/usr/local/bin:/usr/bin:/bin", "PYTHONDONTWRITEBYTECODE": "1"},
        capture_output=True,
        text=True,
        timeout=3,
        preexec_fn=demote,
    )


def test_fuzz_equivalence_without_oracle_access():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert not os.path.islink(AGENT_SCRIPT), "Agent submission must be a regular Python source file"
    assert os.path.exists(ORACLE_PATH), f"Oracle binary missing at {ORACLE_PATH}"

    with open(AGENT_SCRIPT, "r", encoding="utf-8") as f:
        ast.parse(f.read(), filename=AGENT_SCRIPT)

    inputs = generate_inputs(2000)
    expected = [expected_output(value) for value in inputs]

    # Preserve the original oracle-equivalence assertion while independently
    # deriving every answer used to grade the submission.
    for i, (hex_input, derived) in enumerate(zip(inputs, expected)):
        oracle_proc = subprocess.run(
            [ORACLE_PATH, hex_input], capture_output=True, text=True, timeout=3
        )
        assert oracle_proc.stdout.strip() == derived, (
            f"Reference mismatch on input {i}: oracle={oracle_proc.stdout.strip()!r}, "
            f"derived={derived!r}"
        )

    # Remove the oracle and executable copies before invoking the submission,
    # so redirect_handler.py cannot pass by delegating to the supplied binary.
    remove_executable_helpers()
    assert not os.path.exists(ORACLE_PATH)
    saved_modes = lock_writable_staging_areas()
    try:
        for i, (hex_input, derived) in enumerate(zip(inputs, expected)):
            agent_proc = run_as_user(["python3", AGENT_SCRIPT, hex_input])
            assert agent_proc.stdout == derived + "\n", (
                f"Mismatch on input {i} ({hex_input[:30]}...): expected "
                f"{derived!r}, got {agent_proc.stdout!r}"
            )
    finally:
        restore_modes(saved_modes)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
