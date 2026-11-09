#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
import uuid
from pathlib import Path

TARGET_DIR = Path('/app/bloated_dir')
THRESHOLD_SIZE = 1500000
SEARCH_ROOTS = [Path('/app'), Path('/home/user')]


def run(cmd, timeout=120):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, timeout=timeout)


def valid_rust_source(text):
    required = [
        'hard_link',
        'read_dir',
        'read_link',
    ]
    if not all(token in text for token in required):
        return False
    if not ('symlink_metadata' in text or 'is_symlink' in text):
        return False

    streaming = (
        'BufReader' in text or
        'fill_buf' in text or
        'mmap' in text.lower() or
        'memmap' in text.lower() or
        re.search(r'\.read\s*\(\s*&mut', text) is not None
    )
    if not streaming:
        return False

    # Reading each complete file into a Vec is not streaming or memory-mapped I/O.
    if 'read_to_end' in text or re.search(r'(?<![A-Za-z0-9_])(?:std::)?fs::read\s*\(', text):
        return False
    return True


def rust_sources():
    found = []
    for root in SEARCH_ROOTS:
        if not root.exists():
            continue
        for path in root.rglob('*.rs'):
            parts = set(path.parts)
            if 'bloated_dir' in parts or 'target' in parts or '.cargo' in parts:
                continue
            if path.is_file():
                found.append(path)
    return found


def cargo_manifest_for(source):
    parent = source.parent
    while parent != parent.parent:
        manifest = parent / 'Cargo.toml'
        if manifest.is_file():
            return manifest
        parent = parent.parent
    return None


def build_rust_candidates():
    sources = rust_sources()
    assert sources, 'No Rust source file was left in /app or /home/user.'

    candidates = []
    manifests = sorted({cargo_manifest_for(p) for p in sources if cargo_manifest_for(p)})
    covered = set()

    for manifest in manifests:
        project_sources = [p for p in sources if manifest.parent == p.parent or manifest.parent in p.parents]
        text = '\n'.join(p.read_text(errors='ignore') for p in project_sources)
        covered.update(project_sources)
        if not valid_rust_source(text):
            continue

        metadata = run(['cargo', 'metadata', '--format-version', '1', '--no-deps',
                        '--manifest-path', str(manifest)], timeout=60)
        if metadata.returncode != 0:
            continue
        try:
            info = json.loads(metadata.stdout)
        except Exception:
            continue

        built = run(['cargo', 'build', '--manifest-path', str(manifest)], timeout=180)
        if built.returncode != 0:
            continue
        target_dir = Path(info['target_directory']) / 'debug'
        for package in info.get('packages', []):
            for target in package.get('targets', []):
                if 'bin' in target.get('kind', []):
                    binary = target_dir / target['name']
                    if binary.is_file() and os.access(binary, os.X_OK):
                        candidates.append(binary)

    # Also support a program compiled directly with rustc.
    for source in sources:
        if source in covered:
            continue
        text = source.read_text(errors='ignore')
        if 'fn main' not in text or not valid_rust_source(text):
            continue
        output = Path(tempfile.gettempdir()) / ('verifier_rust_' + uuid.uuid4().hex)
        built = run(['rustc', str(source), '-O', '-o', str(output)], timeout=120)
        if built.returncode == 0 and output.is_file():
            candidates.append(output)

    assert candidates, 'No compilable Rust remediation program with traversal, symlink, hard-link, and streaming I/O logic was found.'
    return candidates


def remove_probe(path):
    if path.is_symlink() or path.is_file():
        path.unlink(missing_ok=True)
    elif path.exists():
        shutil.rmtree(path)


def populate_probe(probe, outside):
    remove_probe(probe)
    probe.mkdir(parents=True)
    nested = probe / 'nested' / 'deeper'
    nested.mkdir(parents=True)

    # Deterministic nontrivial data, with equal-sized non-duplicates.
    duplicate = bytes(((i * 73 + 19) % 256 for i in range(300137)))
    distinct = bytearray(duplicate)
    distinct[17] ^= 0x5a
    distinct[-31] ^= 0xa5

    (probe / 'duplicate_a.dat').write_bytes(duplicate)
    (nested / 'duplicate_b.dat').write_bytes(duplicate)
    (nested / 'duplicate_c.dat').write_bytes(duplicate)
    (probe / 'same_size_but_distinct.dat').write_bytes(distinct)
    (nested / 'unique_short.dat').write_bytes(b'unique-content-that-must-survive')

    outside.write_bytes(b'outside-target')
    os.symlink('/etc/passwd', nested / 'absolute_escape')
    os.symlink(os.path.relpath(outside, nested), nested / 'relative_escape')
    os.symlink('/app/bloated_dir/configs/c1.cfg', probe / 'safe_absolute')
    os.symlink('../../../configs/c1.cfg', nested / 'safe_relative')
    return duplicate, bytes(distinct)


def probe_is_correct(probe, duplicate, distinct):
    malicious = [probe / 'nested/deeper/absolute_escape',
                 probe / 'nested/deeper/relative_escape']
    for path in malicious:
        if path.is_symlink() or not path.is_file():
            return False
        if path.read_bytes() != b'INVALID_LINK_REMOVED':
            return False

    safe = [(probe / 'safe_absolute', '/app/bloated_dir/configs/c1.cfg'),
            (probe / 'nested/deeper/safe_relative', '../../../configs/c1.cfg')]
    for path, expected in safe:
        if not path.is_symlink() or os.readlink(path) != expected:
            return False

    duplicates = [probe / 'duplicate_a.dat',
                  probe / 'nested/deeper/duplicate_b.dat',
                  probe / 'nested/deeper/duplicate_c.dat']
    if any(not p.is_file() or p.is_symlink() for p in duplicates):
        return False
    if any(p.read_bytes() != duplicate for p in duplicates):
        return False
    stats = [os.stat(p) for p in duplicates]
    if len({(s.st_dev, s.st_ino) for s in stats}) != 1 or stats[0].st_nlink < 3:
        return False

    distinct_path = probe / 'same_size_but_distinct.dat'
    if distinct_path.read_bytes() != distinct:
        return False
    if os.stat(distinct_path).st_ino == stats[0].st_ino:
        return False
    if (probe / 'nested/deeper/unique_short.dat').read_bytes() != b'unique-content-that-must-survive':
        return False
    return True


def test_program_execution_and_general_behavior():
    candidates = build_rust_candidates()
    probe = TARGET_DIR / ('.verifier_probe_' + uuid.uuid4().hex)
    outside = Path('/tmp') / ('verifier_outside_' + uuid.uuid4().hex)
    succeeded = False
    try:
        for binary in candidates:
            # Try the common target-directory argument interface first, then support
            # programs whose incident target is intentionally fixed in the binary.
            for argv in ([str(binary), str(TARGET_DIR)], [str(binary)]):
                duplicate, distinct = populate_probe(probe, outside)
                try:
                    result = run(argv, timeout=120)
                except Exception:
                    continue
                if result.returncode == 0 and probe_is_correct(probe, duplicate, distinct):
                    succeeded = True
                    break
            if succeeded:
                break
    finally:
        remove_probe(probe)
        outside.unlink(missing_ok=True)

    assert succeeded, 'The compiled Rust program did not traverse and correctly remediate a generated nested test tree.'


def test_malicious_symlinks_remediated():
    malicious_links = [
        TARGET_DIR / 'configs/passwd_link',
        TARGET_DIR / 'cache/log_link',
        TARGET_DIR / 'cache/shadow_link',
    ]
    for path in malicious_links:
        assert os.path.exists(path), f'Expected file at {path} is missing.'
        assert not os.path.islink(path), f'File at {path} is still a symlink.'
        assert os.path.isfile(path), f'File at {path} is not a regular file.'
        with open(path, 'r') as f:
            content = f.read().strip()
        assert content == 'INVALID_LINK_REMOVED', f'Incorrect remediation content at {path}: {content!r}'


def test_safe_symlink_preserved():
    safe_link = TARGET_DIR / 'logs/safe_link'
    expected_target = '/app/bloated_dir/configs/c1.cfg'
    assert os.path.islink(safe_link), f'Safe symlink at {safe_link} was incorrectly removed or altered.'
    assert os.readlink(safe_link) == expected_target


def test_all_original_files_preserved_and_deduplicated():
    assert (TARGET_DIR / 'configs/c1.cfg').read_bytes() == b'config1\n'
    assert (TARGET_DIR / 'configs/c2.cfg').read_bytes() == b'config2\n'

    logs = [TARGET_DIR / f'logs/log_{i}.dat' for i in range(1, 1001)]
    for path in logs:
        assert path.exists(), f'Original log file missing: {path}'
        assert path.is_file() and not path.is_symlink(), f'Original log is not a regular file: {path}'
        assert path.stat().st_size == 1048576, f'Original log size changed: {path}'

    identities = {(p.stat().st_dev, p.stat().st_ino) for p in logs}
    assert len(identities) == 1, 'Not all 1000 identical logs were deduplicated to one inode.'
    assert logs[0].stat().st_nlink >= 1000

    # Retain the original explicit log_1/log_2 hard-link assertions.
    stat1 = os.stat(TARGET_DIR / 'logs/log_1.dat')
    stat2 = os.stat(TARGET_DIR / 'logs/log_2.dat')
    assert stat1.st_ino == stat2.st_ino, 'Duplicate log files do not share the same inode.'
    assert stat1.st_nlink > 1


def test_directory_size():
    assert TARGET_DIR.is_dir(), f'Target directory missing: {TARGET_DIR}'
    output = subprocess.check_output(['du', '-sb', str(TARGET_DIR)], text=True)
    size = int(output.split()[0])
    assert size < THRESHOLD_SIZE, f'Directory size {size} is not below {THRESHOLD_SIZE}.'


def main():
    test_program_execution_and_general_behavior()
    test_malicious_symlinks_remediated()
    test_safe_symlink_preserved()
    test_all_original_files_preserved_and_deduplicated()
    test_directory_size()


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
