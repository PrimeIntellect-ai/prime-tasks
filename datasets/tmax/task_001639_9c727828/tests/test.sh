#!/bin/bash
set -e
mkdir -p /logs/verifier

# Rebuild the fixed corpus from trusted system binaries because the original image
# contains an incorrectly encrypted malicious payload.
python3 - <<'PY'
import os

key = 0x5F3A9B2E
marker = b'AUTH_BYPASS!'
key_bytes = key.to_bytes(4, 'little')
encrypted_marker = bytes(b ^ key_bytes[i % 4] for i, b in enumerate(marker))

os.makedirs('/app/corpus/clean', exist_ok=True)
os.makedirs('/app/corpus/evil', exist_ok=True)

for directory in ('/app/corpus/clean', '/app/corpus/evil'):
    for name in os.listdir(directory):
        path = os.path.join(directory, name)
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)

for source in ('/bin/ls', '/bin/cat', '/bin/echo', '/bin/cp', '/bin/mv'):
    with open(source, 'rb') as f:
        data = f.read()
    name = os.path.basename(source)

    clean_path = os.path.join('/app/corpus/clean', name)
    with open(clean_path, 'wb') as f:
        f.write(data)

    padded = data + b'\0' * ((-len(data)) % 4)
    evil_path = os.path.join('/app/corpus/evil', name)
    with open(evil_path, 'wb') as f:
        f.write(padded + encrypted_marker)

    os.chmod(clean_path, 0o755)
    os.chmod(evil_path, 0o755)
PY

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import pytest

DETECTOR_BIN = "/home/user/detector"
DETECTOR_SOURCE = "/home/user/detector.cpp"
EVIL_CORPUS = "/app/corpus/evil/"
CLEAN_CORPUS = "/app/corpus/clean/"
KEY = 0x5F3A9B2E
MARKER = b"AUTH_BYPASS!"
KEY_BYTES = KEY.to_bytes(4, "little")


def decrypt_contains_marker(data):
    decrypted = bytes(value ^ KEY_BYTES[index % 4] for index, value in enumerate(data))
    return MARKER in decrypted


def encrypted_marker_at(offset):
    return bytes(
        value ^ KEY_BYTES[(offset + index) % 4]
        for index, value in enumerate(MARKER)
    )


def run_detector(path, timeout=5):
    return subprocess.run(
        [DETECTOR_BIN, path], capture_output=True, timeout=timeout
    )


def test_detector_exists_and_executable():
    assert os.path.isfile(DETECTOR_SOURCE), f"Detector source not found at {DETECTOR_SOURCE}"
    assert os.path.isfile(DETECTOR_BIN), f"Detector binary not found at {DETECTOR_BIN}"
    assert os.access(DETECTOR_BIN, os.X_OK), f"Detector binary at {DETECTOR_BIN} is not executable"
    with open(DETECTOR_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Detector is not a compiled ELF executable"


def test_adversarial_corpus():
    assert os.path.isdir(EVIL_CORPUS), f"Evil corpus missing: {EVIL_CORPUS}"
    assert os.path.isdir(CLEAN_CORPUS), f"Clean corpus missing: {CLEAN_CORPUS}"

    evil_files = [os.path.join(EVIL_CORPUS, f) for f in os.listdir(EVIL_CORPUS) if os.path.isfile(os.path.join(EVIL_CORPUS, f))]
    clean_files = [os.path.join(CLEAN_CORPUS, f) for f in os.listdir(CLEAN_CORPUS) if os.path.isfile(os.path.join(CLEAN_CORPUS, f))]

    assert len(evil_files) > 0, "No files found in evil corpus."
    assert len(clean_files) > 0, "No files found in clean corpus."

    evil_bypassed = []
    clean_modified = []

    for filepath in evil_files:
        try:
            result = subprocess.run([DETECTOR_BIN, filepath], capture_output=True, text=True, timeout=5)
            output = result.stdout.strip()
            if output != "MALICIOUS":
                evil_bypassed.append((os.path.basename(filepath), output))
        except Exception as e:
            evil_bypassed.append((os.path.basename(filepath), str(e)))

    for filepath in clean_files:
        try:
            result = subprocess.run([DETECTOR_BIN, filepath], capture_output=True, text=True, timeout=5)
            output = result.stdout.strip()
            if output != "CLEAN":
                clean_modified.append((os.path.basename(filepath), output))
        except Exception as e:
            clean_modified.append((os.path.basename(filepath), str(e)))

    error_messages = []
    if evil_bypassed:
        error_messages.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed:")
        for f, out in evil_bypassed:
            error_messages.append(f"  - {f} (output: {out!r})")

    if clean_modified:
        error_messages.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (false positive):")
        for f, out in clean_modified:
            error_messages.append(f"  - {f} (output: {out!r})")

    if error_messages:
        pytest.fail("\n".join(error_messages))


def test_detector_on_unlabeled_generated_elf_fixtures():
    sources = ['/bin/ls', '/bin/cat', '/bin/echo', '/bin/cp', '/bin/mv']
    cases = []

    with tempfile.TemporaryDirectory(prefix='scan-') as case_dir:
        for index in range(16):
            with open(sources[index % len(sources)], 'rb') as f:
                base = f.read()

            data = bytearray(base)
            data.extend(secrets.token_bytes((-len(data)) % 4))
            data.extend(secrets.token_bytes(4 * (1 + secrets.randbelow(8))))

            make_malicious = (index % 2 == 0)
            if make_malicious:
                offset = len(data)
                assert offset % 4 == 0
                data.extend(encrypted_marker_at(offset))
            else:
                # Match the malicious fixtures' shape without containing the marker.
                while True:
                    candidate = bytearray(data)
                    candidate.extend(secrets.token_bytes(len(MARKER)))
                    if not decrypt_contains_marker(candidate):
                        data = candidate
                        break

            data.extend(secrets.token_bytes(4 * secrets.randbelow(5)))
            expected = b"MALICIOUS\n" if decrypt_contains_marker(data) else b"CLEAN\n"
            assert (expected == b"MALICIOUS\n") == make_malicious

            path = os.path.join(case_dir, secrets.token_hex(12))
            with open(path, 'wb') as f:
                f.write(data)
            os.chmod(path, 0o755)
            cases.append((path, expected))

        random.SystemRandom().shuffle(cases)
        for path, expected in cases:
            result = run_detector(path)
            assert result.returncode == 0, f"Detector exited with {result.returncode} for generated fixture"
            assert result.stdout == expected, (
                f"Expected exact stdout {expected!r}, got {result.stdout!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
