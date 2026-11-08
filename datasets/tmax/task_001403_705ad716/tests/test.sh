#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import subprocess
import tempfile
import uuid
import zipfile

VERIFIER_SCRIPT = '/home/user/verifier.py'
EVAL_CLEAN_DIR = '/app/eval/clean/'
EVAL_EVIL_DIR = '/app/eval/evil/'
SALT = b'KAPPA_99_OMEGA'


def expected_output(expected):
    return ''.join(f'[{name}]: {expected[name]}\n' for name in sorted(expected))


def run_verifier(directory, expected):
    result = subprocess.run(
        ['python3', VERIFIER_SCRIPT, directory],
        capture_output=True,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, f'Script failed with error:\n{result.stderr}'
    assert result.stdout == expected_output(expected), (
        'Output was not exact, complete, and alphabetically ordered.\n'
        f'Expected:\n{expected_output(expected)!r}\nGot:\n{result.stdout!r}'
    )


def manifest_for(files):
    return '\n'.join(
        f'{name} {hashlib.sha256(content).hexdigest()}'
        for name, content in files.items()
    ).encode()


def write_archive(path, files, manifest=None, signature=None,
                  include_manifest=True, include_signature=True):
    if manifest is None:
        manifest = manifest_for(files)
    if signature is None:
        signature = hashlib.sha256(manifest + SALT).hexdigest().encode()

    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for name, content in files.items():
            archive.writestr(name, content)
        if include_manifest:
            archive.writestr('manifest.txt', manifest)
        if include_signature:
            archive.writestr('signature.txt', signature)


def random_zip_name():
    return uuid.uuid4().hex + '.zip'


def test_verifier_script_exists():
    assert os.path.isfile(VERIFIER_SCRIPT), f'Verifier script not found at {VERIFIER_SCRIPT}'


def test_clean_corpus_accepted():
    expected = {
        name: 'ACCEPT'
        for name in os.listdir(EVAL_CLEAN_DIR)
        if name.endswith('.zip')
    }
    run_verifier(EVAL_CLEAN_DIR, expected)


def test_evil_corpus_rejected():
    expected = {
        name: 'REJECT'
        for name in os.listdir(EVAL_EVIL_DIR)
        if name.endswith('.zip')
    }
    run_verifier(EVAL_EVIL_DIR, expected)


def test_hidden_mixed_corpus_exercises_all_validation_rules():
    with tempfile.TemporaryDirectory(prefix='archive-validation-') as directory:
        expected = {}

        def path_for(status):
            name = random_zip_name()
            expected[name] = status
            return os.path.join(directory, name)

        # Valid archives with unpredictable names, contents, and manifest bytes.
        files = {
            'sensor.bin': os.urandom(137),
            'nested/readings.dat': os.urandom(83),
        }
        write_archive(path_for('ACCEPT'), files)
        write_archive(path_for('ACCEPT'), {})

        # Not a zip archive at all.
        with open(path_for('REJECT'), 'wb') as handle:
            handle.write(os.urandom(91))

        # A formerly valid archive with its central directory truncated.
        truncated = path_for('REJECT')
        write_archive(truncated, {'reading.dat': os.urandom(64)})
        with open(truncated, 'r+b') as handle:
            size = handle.seek(0, os.SEEK_END)
            handle.truncate(size - 17)

        content = os.urandom(48)
        files = {'reading.dat': content}

        # Required metadata files must both be present.
        write_archive(path_for('REJECT'), files, include_manifest=False)
        write_archive(path_for('REJECT'), files, include_signature=False)

        # Manifest lists a file that is missing from the archive.
        missing_manifest = manifest_for(files) + b'\nmissing.dat ' + hashlib.sha256(b'x').hexdigest().encode()
        write_archive(path_for('REJECT'), files, manifest=missing_manifest)

        # Archive contains a payload omitted from the manifest.
        extra_files = {'reading.dat': content, 'unauthorized.dat': os.urandom(29)}
        incomplete_manifest = manifest_for({'reading.dat': content})
        write_archive(path_for('REJECT'), extra_files, manifest=incomplete_manifest)

        # Listed checksum does not match the payload.
        bad_checksum_manifest = b'reading.dat ' + (b'0' * 64)
        write_archive(path_for('REJECT'), files, manifest=bad_checksum_manifest)

        # Correct manifest but incorrect signature.
        write_archive(path_for('REJECT'), files, signature=b'0' * 64)

        # Signature must be exact; a trailing newline is invalid.
        manifest = manifest_for(files)
        signed = hashlib.sha256(manifest + SALT).hexdigest().encode()
        write_archive(path_for('REJECT'), files, manifest=manifest, signature=signed + b'\n')

        # Malformed manifest cannot be treated as a valid complete manifest.
        malformed = b'reading.dat not-a-sha256-digest'
        write_archive(path_for('REJECT'), files, manifest=malformed)

        # Non-zip files must not produce output.
        with open(os.path.join(directory, uuid.uuid4().hex + '.txt'), 'wb') as handle:
            handle.write(os.urandom(20))

        run_verifier(directory, expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
