#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
import tempfile
import pytest

DECODER = "/home/user/minimal_decoder.sh"
DROPPER = "/home/user/suspicious_dropper.sh"


def run_with_timeout(command, timeout=5):
    try:
        return subprocess.run(command, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        pytest.fail(f"Command timed out: {command!r}")


def encode_plaintext(plaintext):
    # The dropper serialization reverses the order of the hexadecimal byte pairs.
    pairs = [f"{byte:02x}" for byte in plaintext.encode("ascii")]
    return "".join(reversed(pairs))


def random_plaintext(include_dot=False):
    rng = secrets.SystemRandom()
    alphabet = string.ascii_letters + string.digits + "-_"
    if include_dot:
        left = "".join(rng.choice(alphabet) for _ in range(rng.randint(4, 12)))
        right = "".join(rng.choice(alphabet) for _ in range(rng.randint(4, 12)))
        return left + "." + right
    return "".join(rng.choice(alphabet) for _ in range(rng.randint(7, 24)))


def test_c2_domain_extracted():
    c2_domain_path = "/home/user/c2_domain.txt"
    assert os.path.isfile(c2_domain_path), f"The file {c2_domain_path} does not exist."

    with open(c2_domain_path, "r") as f:
        content = f.read().strip()

    assert content == "super-evil.com", f"Expected 'super-evil.com' in {c2_domain_path}, found '{content}'"


def test_minimal_decoder_exists_and_executable():
    assert os.path.isfile(DECODER), f"The file {DECODER} does not exist."
    assert os.access(DECODER, os.X_OK), f"The file {DECODER} is not executable."


def test_minimal_decoder_functionality():
    # Preserve the original fixed regression cases.
    cases = [("74736574", "test"), ("646162", "bad")]
    for payload, expected in cases:
        result = run_with_timeout([DECODER, payload])
        assert result.returncode == 0, f"minimal_decoder.sh failed with return code {result.returncode}"
        actual = result.stdout.decode("utf-8", errors="replace").strip()
        assert actual == expected, f"Expected {expected!r} from payload {payload!r}, got {actual!r}"


def test_minimal_decoder_general_decoding():
    # Runtime-generated cases prevent implementations that hardcode the public examples.
    plaintexts = [random_plaintext(False), random_plaintext(True), random_plaintext(True)]
    for plaintext in plaintexts:
        payload = encode_plaintext(plaintext)
        result = run_with_timeout([DECODER, payload])
        assert result.returncode == 0, (
            f"minimal_decoder.sh failed on a generated payload with return code {result.returncode}: "
            f"{result.stderr.decode(errors='replace')}"
        )
        assert result.stdout.strip() == plaintext.encode("ascii"), (
            f"minimal_decoder.sh did not reverse and decode all byte pairs for payload {payload!r}"
        )


def test_minimal_decoder_contains_corrected_loop_and_serialization():
    with open(DECODER, "r", errors="replace") as f:
        source = f.read()

    assert re.search(r"\bwhile\b", source), "minimal_decoder.sh does not contain the required decoding loop"
    assert "$1" in source, "minimal_decoder.sh does not consume its first argument"
    assert re.search(r"\$\{\s*[^}]*:\s*\$?i\s*:\s*2\s*\}", source), (
        "minimal_decoder.sh does not extract two-character payload pairs in its loop"
    )
    assert re.search(r"i\s*=\s*\$\(\(\s*i\s*\+\s*2\s*\)\)", source), (
        "minimal_decoder.sh does not advance the loop index by one byte pair"
    )
    assert not re.search(r"i\s*=\s*\$\(\(\s*i\s*\+\s*0\s*\)\)", source), (
        "minimal_decoder.sh still contains the non-progressing loop update"
    )
    assert re.search(r"decoded_hex\s*=.*pair.*decoded_hex", source), (
        "minimal_decoder.sh does not serialize pairs in reverse order"
    )


def test_suspicious_dropper_fixed():
    assert os.path.isfile(DROPPER), f"The file {DROPPER} does not exist."

    result = run_with_timeout(["bash", DROPPER])
    assert result.returncode == 0, f"suspicious_dropper.sh failed with return code {result.returncode}"
    assert b"super-evil.com" in result.stdout, "suspicious_dropper.sh did not output the expected domain."


def test_suspicious_dropper_retains_corrected_loop_and_serialization():
    with open(DROPPER, "r", errors="replace") as f:
        source = f.read()

    assert re.search(r"\bwhile\b", source), "The dropper's decoding loop was removed instead of fixed"
    assert re.search(r"\$\{\s*payload\s*:\s*\$?i\s*:\s*2\s*\}", source), (
        "The dropper no longer extracts payload byte pairs"
    )
    assert re.search(r"i\s*=\s*\$\(\(\s*i\s*\+\s*2\s*\)\)", source), (
        "The dropper does not advance the loop index by one byte pair"
    )
    assert not re.search(r"i\s*=\s*\$\(\(\s*i\s*\+\s*0\s*\)\)", source), (
        "The dropper still contains the non-progressing loop update"
    )
    assert re.search(r"decoded_hex\s*=.*pair.*decoded_hex", source), (
        "The dropper's reverse-pair serialization logic is missing"
    )

    assignment = re.compile(
        r"(?m)^(?P<prefix>\s*payload=)(?:\"[^\"\n]*\"|'[^'\n]*'|[^\s#]+)\s*$"
    )
    assert len(assignment.findall(source)) == 1, (
        "Could not identify exactly one payload assignment in suspicious_dropper.sh"
    )

    # Replace only the payload value and exercise the actual dropper loop on unknown inputs,
    # including 2e, the byte pair that triggered the original infinite loop.
    for plaintext in [random_plaintext(False), random_plaintext(True), random_plaintext(True)]:
        payload = encode_plaintext(plaintext)
        instrumented = assignment.sub(lambda m: m.group("prefix") + '"' + payload + '"', source, count=1)
        with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as temporary:
            temporary.write(instrumented)
            temporary_path = temporary.name
        try:
            result = run_with_timeout(["bash", temporary_path])
        finally:
            os.unlink(temporary_path)

        assert result.returncode == 0, (
            f"The corrected dropper failed on generated payload {payload!r}: "
            f"{result.stderr.decode(errors='replace')}"
        )
        assert result.stdout.strip() == plaintext.encode("ascii"), (
            "The dropper does not actually decode its payload through the corrected serialization loop"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
