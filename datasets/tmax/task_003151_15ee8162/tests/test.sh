#!/bin/bash
set -e
mkdir -p /logs/verifier

FLOCK_BIN="$(readlink -f "$(command -v flock)")"
MKTEMP_BIN="$(readlink -f "$(command -v mktemp)")"
FLOCK_REAL="${FLOCK_BIN}.verifier-real"
MKTEMP_REAL="${MKTEMP_BIN}.verifier-real"
LOCK_LOG="/tmp/verifier-flock.log"
MKTEMP_LOG="/tmp/verifier-mktemp.log"

restore_tools() {
    if [ -e "$FLOCK_REAL" ]; then
        rm -f "$FLOCK_BIN"
        mv "$FLOCK_REAL" "$FLOCK_BIN"
    fi
    if [ -e "$MKTEMP_REAL" ]; then
        rm -f "$MKTEMP_BIN"
        mv "$MKTEMP_REAL" "$MKTEMP_BIN"
    fi
}
trap restore_tools EXIT

rm -f "$LOCK_LOG" "$MKTEMP_LOG" "$FLOCK_REAL" "$MKTEMP_REAL"
mv "$FLOCK_BIN" "$FLOCK_REAL"
cat > "$FLOCK_BIN" <<EOF
#!/bin/bash
printf 'flock\n' >> '$LOCK_LOG'
exec '$FLOCK_REAL' "\$@"
EOF
chmod 755 "$FLOCK_BIN"

mv "$MKTEMP_BIN" "$MKTEMP_REAL"
cat > "$MKTEMP_BIN" <<EOF
#!/bin/bash
printf 'mktemp\n' >> '$MKTEMP_LOG'
exec '$MKTEMP_REAL' "\$@"
EOF
chmod 755 "$MKTEMP_BIN"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path

import pytest

EVIL_DIR = Path('/app/grader/evil')
CLEAN_DIR = Path('/app/grader/clean')
SCRIPT_PATH = Path('/home/user/cleanup.sh')
MANIFEST_PATH = Path('/tmp/global_manifest.txt')
LOCK_LOG = Path('/tmp/verifier-flock.log')
MKTEMP_LOG = Path('/tmp/verifier-mktemp.log')
FIXED_CLEAN_NAMES = {
    'clean_maintenance.wav',
    'clean_meeting.wav',
    'clean_lunch.wav',
}


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(65536), b''):
            h.update(block)
    return h.hexdigest()


def manifest_entries(path):
    assert path.is_file(), f'Manifest file missing at {path}'
    entries = []
    for line in path.read_text(errors='strict').splitlines():
        match = re.fullmatch(r'([0-9a-fA-F]{64})  (.+)', line)
        assert match, f'Invalid manifest line (expected <checksum>  <filepath>): {line!r}'
        entries.append((match.group(1).lower(), match.group(2)))
    return entries


def run_parallel(calls, env=None):
    processes = [
        subprocess.Popen(['bash', str(SCRIPT_PATH), str(directory), str(manifest)], env=env)
        for directory, manifest in calls
    ]
    try:
        returncodes = [p.wait(timeout=600) for p in processes]
    except subprocess.TimeoutExpired:
        for p in processes:
            p.kill()
        raise AssertionError('cleanup.sh timed out')
    assert returncodes == [0] * len(processes), f'cleanup.sh returned {returncodes}'


@pytest.fixture(scope='session')
def completed_runs():
    assert SCRIPT_PATH.is_file(), f'Agent script missing at {SCRIPT_PATH}'
    assert os.access(SCRIPT_PATH, os.X_OK), f'Agent script at {SCRIPT_PATH} is not executable'
    subprocess.run(['bash', '-n', str(SCRIPT_PATH)], check=True)

    source = SCRIPT_PATH.read_text(errors='replace')
    code = '\n'.join(line for line in source.splitlines() if not line.lstrip().startswith('#'))
    assert re.search(r'\bffprobe\b', code), 'cleanup.sh does not validate audio with ffprobe'
    assert re.search(r'whisper|transcrib', code, re.I), 'cleanup.sh does not contain a transcription step'
    assert re.search(r'\bflock\b', code), 'cleanup.sh does not use flock for manifest writes'
    assert re.search(r'\bmktemp\b', code), 'cleanup.sh does not create temporary files securely with mktemp'
    assert re.search(r'\btrap\b', code) and re.search(r'EXIT|\b0\b', code), 'cleanup.sh does not arrange temporary-file cleanup with an exit trap'
    keywords = ('cryptocurrency', 'timeshare', 'viagra')
    assert (all(k in source.lower() for k in keywords) or
            ('voicemail_99.wav' in source and re.search(r'whisper|transcrib', source, re.I))), \
        'cleanup.sh neither contains the discovered keywords nor derives them from voicemail_99.wav'

    fixed_paths = {p.name: p for p in CLEAN_DIR.glob('*.wav')}
    assert set(fixed_paths) == FIXED_CLEAN_NAMES, 'The original clean corpus is incomplete before verification'
    fixed_hashes = {str(p): sha256(p) for p in fixed_paths.values()}

    MANIFEST_PATH.unlink(missing_ok=True)
    run_parallel([(EVIL_DIR, MANIFEST_PATH), (CLEAN_DIR, MANIFEST_PATH)])

    root = Path(tempfile.mkdtemp(prefix='voicemail-verifier-'))
    first = root / ('incoming ' + uuid.uuid4().hex)
    second = root / ('archive ' + uuid.uuid4().hex)
    temp_area = root / 'secure-temp'
    first.mkdir()
    second.mkdir()
    temp_area.mkdir()
    dynamic_manifest = root / ('manifest ' + uuid.uuid4().hex + '.txt')

    clean_one = first / ('customer callback ' + uuid.uuid4().hex + '.wav')
    clean_two = second / ('operations notice ' + uuid.uuid4().hex + '.wav')
    spam_one = first / ('message ' + uuid.uuid4().hex + '.wav')
    spam_two = second / ('recording ' + uuid.uuid4().hex + '.wav')
    corrupt_one = first / ('damaged ' + uuid.uuid4().hex + '.wav')
    corrupt_two = second / ('invalid ' + uuid.uuid4().hex + '.wav')

    subprocess.run(['espeak', '-w', str(clean_one), 'Please return the customer call about routine network maintenance tomorrow.'], check=True)
    subprocess.run(['espeak', '-w', str(clean_two), 'The engineering status meeting begins after lunch today.'], check=True)
    subprocess.run(['espeak', '-w', str(spam_one), 'Urgent offer, invest in cryptocurrency for an immediate reward.'], check=True)
    subprocess.run(['espeak', '-w', str(spam_two), 'This timeshare promotion includes discounted viagra delivered today.'], check=True)
    corrupt_one.write_text('This is not audio data. Random token ' + uuid.uuid4().hex)
    corrupt_two.write_bytes(os.urandom(8192))

    expected_dynamic = {
        str(clean_one): sha256(clean_one),
        str(clean_two): sha256(clean_two),
    }
    LOCK_LOG.write_text('')
    MKTEMP_LOG.write_text('')
    env = os.environ.copy()
    env['TMPDIR'] = str(temp_area)
    run_parallel([(first, dynamic_manifest), (second, dynamic_manifest)], env=env)

    yield {
        'fixed_hashes': fixed_hashes,
        'dynamic_manifest': dynamic_manifest,
        'expected_dynamic': expected_dynamic,
        'dynamic_dirs': (first, second),
        'dynamic_clean': (clean_one, clean_two),
        'dynamic_spam': (spam_one, spam_two),
        'dynamic_corrupt': (corrupt_one, corrupt_two),
        'temp_area': temp_area,
    }
    shutil.rmtree(root, ignore_errors=True)


def test_evil_corpus_rejected(completed_runs):
    remaining = [str(p) for p in EVIL_DIR.rglob('*.wav')]
    assert not remaining, f'{len(remaining)} evil files bypassed deletion: {remaining}'


def test_clean_corpus_preserved(completed_runs):
    expected = completed_runs['fixed_hashes']
    actual_paths = {str(p) for p in CLEAN_DIR.rglob('*.wav')}
    assert actual_paths == set(expected), f'Clean files were deleted or unexpected WAVs appeared: {actual_paths}'
    for path, digest in expected.items():
        assert sha256(path) == digest, f'Clean file was modified: {path}'


def test_manifest_correctness(completed_runs):
    expected = completed_runs['fixed_hashes']
    actual = manifest_entries(MANIFEST_PATH)
    expected_entries = {(digest, path) for path, digest in expected.items()}
    assert set(actual) == expected_entries, f'Manifest differs from clean corpus: {actual}'
    assert len(actual) == len(expected_entries), 'Manifest contains duplicate, extra, or missing entries'


def test_randomized_corpus_and_transcription(completed_runs):
    for path in completed_runs['dynamic_clean']:
        assert path.is_file(), f'Clean randomized WAV was not preserved: {path}'
        assert sha256(path) == completed_runs['expected_dynamic'][str(path)], f'Clean WAV was modified: {path}'
    for path in completed_runs['dynamic_spam'] + completed_runs['dynamic_corrupt']:
        assert not path.exists(), f'Spam or corrupt randomized WAV survived: {path}'

    expected = {(digest, path) for path, digest in completed_runs['expected_dynamic'].items()}
    actual = manifest_entries(completed_runs['dynamic_manifest'])
    assert set(actual) == expected, f'Randomized manifest is incorrect: {actual}'
    assert len(actual) == len(expected), 'Randomized manifest has duplicate or extra entries'


def test_locking_and_secure_temporary_cleanup(completed_runs):
    lock_calls = LOCK_LOG.read_text().splitlines() if LOCK_LOG.exists() else []
    mktemp_calls = MKTEMP_LOG.read_text().splitlines() if MKTEMP_LOG.exists() else []
    assert len(lock_calls) >= 2, 'flock was not actually invoked by both concurrent cleanup runs'
    assert len(mktemp_calls) >= 2, 'mktemp was not actually invoked by both cleanup runs'
    assert not any(completed_runs['temp_area'].iterdir()), 'Temporary transcription files were not removed'

    allowed = set(completed_runs['dynamic_clean'])
    leftovers = set()
    for directory in completed_runs['dynamic_dirs']:
        leftovers.update(p for p in directory.iterdir() if p.is_file())
    assert leftovers == allowed, f'Unexpected transcription or temporary files remain: {leftovers - allowed}'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
