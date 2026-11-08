#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import itertools
import math
import os
import pwd
import secrets
import socket
import stat
import subprocess
import tempfile
import wave

import pytest
import requests

SSH_DIR = "/home/user/.ssh"
PRIVATE_KEY = SSH_DIR + "/id_ed25519"
PUBLIC_KEY = PRIVATE_KEY + ".pub"
SERVER_SCRIPT = "/home/user/server.py"
AUDIO_PATH = "/app/intercepted.wav"
CIPHERTEXT_PATH = "/home/user/traffic.enc"

DIGIT_WORDS = {
    "0": "zero", "1": "one", "2": "two", "3": "three", "4": "four",
    "5": "five", "6": "six", "7": "seven", "8": "eight", "9": "nine",
}
ALLOWED_PAYLOAD_BYTES = set(b"ABCDEFGHIJKLMNOPQRSTUVWXYZ _:")
LETTER_FREQUENCY = {
    "E": 12.70, "T": 9.06, "A": 8.17, "O": 7.51, "I": 6.97,
    "N": 6.75, "S": 6.33, "H": 6.09, "R": 5.99, "D": 4.25,
    "L": 4.03, "C": 2.78, "U": 2.76, "M": 2.41, "W": 2.36,
    "F": 2.23, "G": 2.02, "Y": 1.97, "P": 1.93, "B": 1.49,
    "V": 0.98, "K": 0.77, "J": 0.15, "X": 0.15, "Q": 0.10,
    "Z": 0.07,
}
COMMON_NGRAMS = (
    "THE", "AND", "ING", "ION", "TIO", "ENT", "ATI", "FOR", "HER",
    "TER", "HAT", "HIS", "THA", "ERE", "ATE", "ALL", "ETH", "HES",
    "VER", "HEN", "OPE", "PER", "ERA", "CON", "DEN", "RED", "GET",
    "ACQ", "QUI", "IRE",
)


def _same_waveform(first, second):
    try:
        with wave.open(first, "rb") as a, wave.open(second, "rb") as b:
            return a.getparams() == b.getparams() and a.readframes(a.getnframes()) == b.readframes(b.getnframes())
    except (wave.Error, EOFError):
        return False


def _plaintext_score(data):
    try:
        text = data.decode("ascii")
    except UnicodeDecodeError:
        return -1e100
    score = 0.0
    for ch in text:
        if ch in LETTER_FREQUENCY:
            score += math.log(LETTER_FREQUENCY[ch] + 0.1)
        elif ch in " _:":
            score += 1.0
        else:
            score -= 20.0
    score += sum(text.count(ngram) * 5.0 for ngram in COMMON_NGRAMS)
    return score


def _derive_pin_and_payload():
    with open(CIPHERTEXT_PATH, "r", encoding="ascii") as f:
        raw_hex = "".join(f.read().split())
    ciphertext = bytes.fromhex(raw_hex)
    assert ciphertext, "Encrypted payload is empty"

    ranked = []
    # Determine both the key length and digits from the encrypted artifact. The
    # resulting candidate must independently reproduce the intercepted waveform.
    for key_length in range(1, 11):
        choices = []
        for offset in range(key_length):
            column = ciphertext[offset::key_length]
            valid = []
            for digit in b"0123456789":
                if all((value ^ digit) in ALLOWED_PAYLOAD_BYTES for value in column):
                    valid.append(digit)
            if not valid:
                choices = []
                break
            choices.append(valid)

        if not choices:
            continue
        combination_count = math.prod(len(group) for group in choices)
        if combination_count > 10000:
            continue

        for candidate_tuple in itertools.product(*choices):
            key = bytes(candidate_tuple)
            plaintext = bytes(value ^ key[i % len(key)] for i, value in enumerate(ciphertext))
            ranked.append((_plaintext_score(plaintext), key.decode("ascii"), plaintext))

    assert ranked, "Could not derive any numeric repeating-XOR key candidates"
    ranked.sort(reverse=True, key=lambda item: item[0])

    with tempfile.TemporaryDirectory() as tmp:
        generated = os.path.join(tmp, "candidate.wav")
        for _, pin, plaintext in ranked[:1000]:
            phrase = " ".join(DIGIT_WORDS[digit] for digit in pin)
            subprocess.run(
                ["espeak", "-w", generated, phrase],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if _same_waveform(AUDIO_PATH, generated):
                return pin, plaintext.decode("utf-8")

    pytest.fail("No numeric XOR key candidate matched the intercepted audio")


@pytest.fixture(scope="session")
def intelligence():
    return _derive_pin_and_payload()


def _assert_owned_by_user(path):
    expected = pwd.getpwnam("user")
    info = os.stat(path)
    assert info.st_uid == expected.pw_uid, f"{path} must be owned by user"
    assert info.st_gid == expected.pw_gid, f"{path} must have user's primary group"


def test_ssh_directory_permissions_and_ownership():
    assert os.path.isdir(SSH_DIR), f"Directory {SSH_DIR} does not exist."
    mode = stat.S_IMODE(os.stat(SSH_DIR).st_mode)
    assert mode == 0o700, f"Permissions on {SSH_DIR} should be 700, got {oct(mode)}"
    _assert_owned_by_user(SSH_DIR)


def test_ssh_private_key_permissions_and_ownership():
    assert os.path.isfile(PRIVATE_KEY), f"Private key {PRIVATE_KEY} does not exist."
    mode = stat.S_IMODE(os.stat(PRIVATE_KEY).st_mode)
    assert mode == 0o600, f"Permissions on {PRIVATE_KEY} should be 600, got {oct(mode)}"
    _assert_owned_by_user(PRIVATE_KEY)


def test_ed25519_keypair_is_valid_and_matching():
    assert os.path.isfile(PUBLIC_KEY), f"Public key {PUBLIC_KEY} does not exist."
    assert not os.path.islink(PRIVATE_KEY), "Private key must not be a symbolic link"
    assert not os.path.islink(PUBLIC_KEY), "Public key must not be a symbolic link"
    _assert_owned_by_user(PUBLIC_KEY)

    public_mode = stat.S_IMODE(os.stat(PUBLIC_KEY).st_mode)
    assert public_mode == 0o644, f"Public key should have standard mode 644, got {oct(public_mode)}"

    with open(PUBLIC_KEY, "r", encoding="utf-8") as f:
        fields = f.read().strip().split()
    assert len(fields) >= 2, "Malformed SSH public key"
    assert fields[0] == "ssh-ed25519", "Public key is not Ed25519"
    decoded = base64.b64decode(fields[1], validate=True)
    assert decoded.startswith(b"\x00\x00\x00\x0bssh-ed25519"), "Invalid Ed25519 public-key blob"

    result = subprocess.run(
        ["ssh-keygen", "-y", "-f", PRIVATE_KEY],
        check=True,
        text=True,
        capture_output=True,
    )
    derived = result.stdout.strip().split()
    assert len(derived) >= 2 and derived[0] == "ssh-ed25519", "Private key is not a valid Ed25519 key"
    assert derived[:2] == fields[:2], "Private and public SSH keys do not form a keypair"


def _ipv4_listener_inode(port):
    wanted_port = f"{port:04X}"
    with open("/proc/net/tcp", "r", encoding="ascii") as f:
        next(f)
        for line in f:
            fields = line.split()
            address, found_port = fields[1].split(":")
            state = fields[3]
            if address == "00000000" and found_port.upper() == wanted_port and state == "0A":
                return fields[9]
    pytest.fail(f"No TCP listener is bound to IPv4 0.0.0.0:{port}")


def _listener_processes(inode):
    needle = f"socket:[{inode}]"
    owners = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    if os.readlink(os.path.join(fd_dir, fd)) == needle:
                        with open(f"/proc/{pid}/cmdline", "rb") as f:
                            cmdline = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
                        owners.append(cmdline)
                        break
                except (FileNotFoundError, PermissionError, OSError):
                    pass
        except (FileNotFoundError, PermissionError):
            pass
    return owners


def test_server_script_owns_wildcard_listeners():
    assert os.path.isfile(SERVER_SCRIPT), f"Server script {SERVER_SCRIPT} does not exist"
    assert not os.path.islink(SERVER_SCRIPT), "server.py must be a regular file, not a symlink"
    for port in (8000, 9000):
        inode = _ipv4_listener_inode(port)
        owners = _listener_processes(inode)
        assert owners, f"Could not identify the process listening on port {port}"
        assert any(SERVER_SCRIPT in command for command in owners), (
            f"Port {port} is not being served by {SERVER_SCRIPT}; owners were {owners!r}"
        )


def test_http_pubkey_service():
    with open(PUBLIC_KEY, "r", encoding="utf-8") as f:
        expected_pubkey = f.read()
    try:
        response = requests.get("http://127.0.0.1:8000/pubkey", timeout=3)
    except requests.RequestException as error:
        pytest.fail(f"HTTP request to port 8000 failed: {error}")
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    assert response.text == expected_pubkey, "HTTP response body does not exactly match the public key file"


def _tcp_exchange(message):
    chunks = []
    with socket.create_connection(("127.0.0.1", 9000), timeout=3) as connection:
        connection.settimeout(3)
        connection.sendall(message)
        connection.shutdown(socket.SHUT_WR)
        while True:
            data = connection.recv(4096)
            if not data:
                break
            chunks.append(data)
    return b"".join(chunks)


@pytest.mark.parametrize("trailing_newline", [False, True])
def test_tcp_auth_service_correct_pin(intelligence, trailing_newline):
    pin, payload = intelligence
    request = pin.encode("utf-8") + (b"\n" if trailing_newline else b"")
    response = _tcp_exchange(request)
    assert response.decode("utf-8") == payload, f"Expected exact decrypted payload, got {response!r}"


def test_tcp_auth_service_rejects_multiple_unpredictable_incorrect_pins(intelligence):
    pin, _ = intelligence
    wrong_pins = {"", "0" * len(pin), pin + "0", " " + pin, pin + " "}
    while len(wrong_pins) < 10:
        candidate = "".join(str(secrets.randbelow(10)) for _ in range(len(pin)))
        if candidate != pin:
            wrong_pins.add(candidate)

    for wrong_pin in wrong_pins:
        response = _tcp_exchange((wrong_pin + "\n").encode("utf-8"))
        assert response.decode("utf-8") == "ACCESS DENIED", (
            f"Incorrect PIN {wrong_pin!r} did not receive exact ACCESS DENIED response: {response!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
