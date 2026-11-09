#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import secrets
import string
import subprocess
from pathlib import Path

PROJECT = Path('/home/user/decoder')
OUTPUT = Path('/home/user/extracted_payload.txt')
TRANSMISSION = Path('/app/transmission.wav')
REFERENCE = 'CRITICAL_PAYLOAD_INITIATED_0x8F2A_OVERRIDE_ACTIVE'


def levenshtein_distance(s1, s2):
    if len(s1) < len(s2):
        return levenshtein_distance(s2, s1)
    if len(s2) == 0:
        return len(s1)

    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row

    return previous_row[-1]


def calculate_accuracy(reference, candidate):
    distance = levenshtein_distance(reference, candidate)
    max_len = max(len(reference), len(candidate))
    if max_len == 0:
        return 1.0
    return 1.0 - (distance / max_len)


def run_decoder():
    env = os.environ.copy()
    env['DECODER_KEY'] = '7734'
    result = subprocess.run(
        ['cargo', 'run', '--quiet'],
        cwd=PROJECT,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f'Decoder failed to compile or run. stdout: {result.stdout!r}; '
        f'stderr: {result.stderr!r}'
    )
    assert OUTPUT.is_file(), 'Decoder did not create /home/user/extracted_payload.txt'


def test_extracted_payload_accuracy():
    assert OUTPUT.is_file(), f'Expected output file is missing at {OUTPUT}'

    candidate = OUTPUT.read_text().strip()
    accuracy = calculate_accuracy(REFERENCE, candidate)

    assert accuracy >= 0.95, (
        f'Extracted payload accuracy {accuracy:.4f} is below the threshold of 0.95. '
        f"Candidate text: '{candidate}'"
    )


def test_project_compiles_runs_and_decodes_actual_transmission():
    cargo_toml = PROJECT / 'Cargo.toml'
    main_rs = PROJECT / 'src/main.rs'
    assert cargo_toml.is_file(), 'Missing decoder/Cargo.toml'
    assert main_rs.is_file(), 'Missing decoder/src/main.rs'
    assert TRANSMISSION.is_file(), 'Missing /app/transmission.wav'

    original_audio = TRANSMISSION.read_bytes()
    original_output = OUTPUT.read_bytes() if OUTPUT.exists() else None

    try:
        # Execute the submitted Rust project on the original transmission.
        OUTPUT.unlink(missing_ok=True)
        run_decoder()
        assert OUTPUT.read_text() == REFERENCE, (
            'Running the decoder on the original transmission did not produce '
            'the exact extracted string'
        )

        # Exercise the decoder with an unpredictable payload. Ensure its standard
        # base64 representation contains both characters that distinguish the
        # STANDARD alphabet from URL_SAFE.
        alphabet = string.ascii_letters + string.digits + string.punctuation
        while True:
            dynamic_payload = 'VERIFY_' + ''.join(
                secrets.choice(alphabet) for _ in range(96)
            )
            encoded = base64.b64encode(dynamic_payload.encode('utf-8'))
            if b'+' in encoded and b'/' in encoded:
                break

        marker = original_audio.find(b'MARKER')
        assert marker >= 0, 'Original transmission has no MARKER'
        TRANSMISSION.write_bytes(original_audio[:marker] + b'MARKER' + encoded)

        OUTPUT.unlink(missing_ok=True)
        run_decoder()
        assert OUTPUT.read_text() == dynamic_payload, (
            'The Rust decoder did not extract and STANDARD-base64-decode the '
            'payload from the supplied transmission'
        )
    finally:
        TRANSMISSION.write_bytes(original_audio)
        if original_output is None:
            OUTPUT.unlink(missing_ok=True)
        else:
            OUTPUT.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
