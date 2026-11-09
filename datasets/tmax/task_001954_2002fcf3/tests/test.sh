#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess
import tarfile
import tempfile
import uuid
from pathlib import Path

import pytest

DETECTOR_BIN = Path('/home/user/forensics/detector/target/release/detector')
PROJECT_DIR = Path('/home/user/forensics/detector')
HIDDEN_EVIL_DIR = Path('/app/verifier/hidden_evil')
HIDDEN_CLEAN_DIR = Path('/app/verifier/hidden_clean')
EXTRACTED_DIR = Path('/home/user/forensics/scripts')
VIDEO = Path('/app/evidence/screen_capture.mp4')
ENCRYPTED_ARCHIVE = Path('/app/evidence/scripts.tar.gz.enc')
KEY = 'KEY-8f4e2b1a9c7d5e6f3b2a1c0d9e8f7a6b'
LINE_RE = re.compile(r'^(EVIL|CLEAN): ([^/\\]+)$')


def run_detector(binary, directory):
    binary = Path(binary)
    assert binary.is_file(), f'Detector binary not found at {binary}'
    assert os.access(binary, os.X_OK), f'Detector binary at {binary} is not executable'
    assert binary.read_bytes()[:4] == b'\x7fELF', f'{binary} is not an ELF executable'

    try:
        result = subprocess.run(
            [str(binary), str(directory)],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f'Detector binary timed out when analyzing {directory}')

    assert result.returncode == 0, (
        f'Detector binary exited with non-zero code {result.returncode} for {directory}\n'
        f'Stderr: {result.stderr}'
    )
    return result.stdout.splitlines()


def assert_classifications(binary, directory, expected):
    lines = run_detector(binary, directory)
    assert len(lines) == len(expected), (
        f'Expected exactly {len(expected)} output lines, got {len(lines)}: {lines!r}'
    )

    results = {}
    for line in lines:
        match = LINE_RE.fullmatch(line)
        assert match is not None, f'Malformed or extra output line: {line!r}'
        label, filename = match.groups()
        assert filename not in results, f'Duplicate output for {filename!r}'
        results[filename] = label

    assert set(results) == set(expected), (
        f'Output filenames differ from directory files. Expected {set(expected)!r}, '
        f'got {set(results)!r}'
    )
    assert results == expected, f'Incorrect classifications: expected {expected!r}, got {results!r}'


def test_stage1_evidence_and_extraction():
    assert VIDEO.is_file(), f'Missing video evidence at {VIDEO}'
    assert ENCRYPTED_ARCHIVE.is_file(), f'Missing encrypted archive at {ENCRYPTED_ARCHIVE}'
    assert EXTRACTED_DIR.is_dir(), f'Missing extracted scripts directory at {EXTRACTED_DIR}'

    # Confirm the designated video frame contains the unique visual evidence frame.
    frame_data = []
    for frame_number in (1041, 1042, 1043):
        result = subprocess.run(
            [
                'ffmpeg', '-v', 'error', '-i', str(VIDEO),
                '-vf', f'select=eq(n\\,{frame_number})', '-frames:v', '1',
                '-f', 'image2pipe', '-vcodec', 'png', 'pipe:1',
            ],
            capture_output=True,
            timeout=30,
        )
        assert result.returncode == 0 and result.stdout, (
            f'Could not extract evidence frame {frame_number}: '
            f'{result.stderr.decode(errors="replace")}'
        )
        frame_data.append(result.stdout)
    assert frame_data[1] != frame_data[0] and frame_data[1] != frame_data[2], (
        'The expected unique key-bearing video frame was not found'
    )

    # Independently decrypt the supplied archive with the full recovered key and
    # compare every extracted file byte-for-byte with the agent's Stage 1 output.
    with tempfile.TemporaryDirectory() as tmp:
        decrypted = Path(tmp) / 'scripts.tar.gz'
        result = subprocess.run(
            [
                'openssl', 'enc', '-d', '-aes-256-cbc', '-pbkdf2',
                '-pass', f'pass:{KEY}', '-in', str(ENCRYPTED_ARCHIVE),
                '-out', str(decrypted),
            ],
            capture_output=True,
            timeout=30,
        )
        assert result.returncode == 0, f'Archive decryption failed: {result.stderr.decode(errors="replace")}'

        expected_files = {}
        expected_dirs = set()
        with tarfile.open(decrypted, 'r:gz') as archive:
            for member in archive.getmembers():
                normalized = member.name.rstrip('/')
                assert normalized and not normalized.startswith('/') and '..' not in Path(normalized).parts
                if member.isdir():
                    expected_dirs.add(normalized)
                elif member.isfile():
                    handle = archive.extractfile(member)
                    assert handle is not None
                    expected_files[normalized] = handle.read()
                else:
                    pytest.fail(f'Unexpected non-file archive member: {member.name}')

    actual_files = {}
    actual_dirs = set()
    for root, dirs, files in os.walk(EXTRACTED_DIR):
        root_path = Path(root)
        for dirname in dirs:
            path = root_path / dirname
            assert not path.is_symlink(), f'Extracted directory must not be a symlink: {path}'
            actual_dirs.add(path.relative_to(EXTRACTED_DIR).as_posix())
        for filename in files:
            path = root_path / filename
            assert path.is_file() and not path.is_symlink(), f'Invalid extracted file: {path}'
            actual_files[path.relative_to(EXTRACTED_DIR).as_posix()] = path.read_bytes()

    assert actual_dirs == expected_dirs, f'Extracted directory layout is wrong: {actual_dirs!r}'
    assert actual_files == expected_files, 'Extracted scripts do not exactly match the decrypted archive'


def test_detector_on_provided_corpora():
    evil_dir = EXTRACTED_DIR / 'evil'
    clean_dir = EXTRACTED_DIR / 'clean'
    assert evil_dir.is_dir() and clean_dir.is_dir()
    assert_classifications(DETECTOR_BIN, evil_dir, {p.name: 'EVIL' for p in evil_dir.iterdir() if p.is_file()})
    assert_classifications(DETECTOR_BIN, clean_dir, {p.name: 'CLEAN' for p in clean_dir.iterdir() if p.is_file()})


def test_detector_on_original_hidden_corpora():
    assert HIDDEN_EVIL_DIR.is_dir(), f'Missing hidden evil corpus directory at {HIDDEN_EVIL_DIR}'
    assert HIDDEN_CLEAN_DIR.is_dir(), f'Missing hidden clean corpus directory at {HIDDEN_CLEAN_DIR}'
    assert_classifications(
        DETECTOR_BIN,
        HIDDEN_EVIL_DIR,
        {name: 'EVIL' for name in os.listdir(HIDDEN_EVIL_DIR)},
    )
    assert_classifications(
        DETECTOR_BIN,
        HIDDEN_CLEAN_DIR,
        {name: 'CLEAN' for name in os.listdir(HIDDEN_CLEAN_DIR)},
    )


def create_adversarial_corpus(directory):
    samples = [
        ('EVIL', '#!/bin/sh\n[ -e /.dockerenv ] && exit 0\necho payload\n'),
        ('EVIL', '#!/bin/bash\nif grep -q docker /proc/1/cgroup; then exit 1; fi\necho payload\n'),
        ('EVIL', '#!/bin/sh\ngrep -Eq "kubepods|containerd" /proc/1/cgroup && exit 0\nrun_payload\n'),
        ('EVIL', '#!/bin/bash\nmode=$(stat -c %a /etc/passwd)\n[ "$mode" = 644 ] || exit 0\necho payload\n'),
        ('CLEAN', '#!/bin/sh\necho "rotating application logs"\nfind /var/log -name "*.old" -delete\n'),
        ('CLEAN', '#!/bin/bash\nif [ -f /etc/app.conf ]; then\n  cp /etc/app.conf /backup/app.conf\nfi\n'),
        ('CLEAN', '#!/bin/sh\nchmod 640 /var/log/app.log\necho "permissions updated"\n'),
        ('CLEAN', '#!/bin/bash\ntar -czf /backup/home.tar.gz /home\necho "backup complete"\n'),
    ]
    expected = {}
    for label, content in samples:
        filename = f'{uuid.uuid4().hex}.sh'
        (directory / filename).write_text(content)
        expected[filename] = label
    return expected


def test_rust_project_and_unpredictable_mixed_corpus():
    assert (PROJECT_DIR / 'Cargo.toml').is_file(), 'Missing Rust Cargo.toml'
    assert (PROJECT_DIR / 'src' / 'main.rs').is_file(), 'Missing Rust src/main.rs'

    with tempfile.TemporaryDirectory() as build_tmp, tempfile.TemporaryDirectory() as corpus_tmp:
        env = os.environ.copy()
        env['CARGO_TARGET_DIR'] = build_tmp
        try:
            result = subprocess.run(
                ['cargo', 'build', '--release'],
                cwd=PROJECT_DIR,
                env=env,
                capture_output=True,
                text=True,
                timeout=180,
            )
        except subprocess.TimeoutExpired:
            pytest.fail('Rust project timed out while rebuilding')
        assert result.returncode == 0, f'Rust project did not build:\n{result.stdout}\n{result.stderr}'

        rebuilt = Path(build_tmp) / 'release' / 'detector'
        assert rebuilt.is_file(), 'Rust project did not build a detector executable'
        rebuilt.chmod(rebuilt.stat().st_mode | stat.S_IXUSR)

        corpus = Path(corpus_tmp)
        expected = create_adversarial_corpus(corpus)
        # Both the submitted release artifact and a fresh build from the Rust
        # sources must handle unpredictable filenames in one mixed directory.
        assert_classifications(DETECTOR_BIN, corpus, expected)
        assert_classifications(rebuilt, corpus, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
