#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ctypes
import hashlib
import os
import shlex
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

DOCS_DIR = Path('/home/user/docs')
MANIFEST_PATH = DOCS_DIR / 'manifest.sha256'

EXPECTED = {
    'intro.md': b'''---\ntitle: Introduction\nstatus: published\n---\nWelcome to the NovaBrand documentation.\nNovaBrand provides top-tier solutions.\n''',
    'setup.md': b'''---\ntitle: Setup Guide\nstatus: published\n---\nTo install NovaBrand, run the installer.\nThank you for choosing NovaBrand.\n''',
    'draft_api.md': b'''---\ntitle: API Reference\nstatus: draft\n---\nThe LegacyBrand API is currently under construction.\nPlease check back later for LegacyBrand updates.\n''',
    'notes.txt': b'''status: published\nThese are some personal notes about LegacyBrand.\n''',
}


def published_markdown_files():
    result = []
    for path in DOCS_DIR.rglob('*.md'):
        if path.is_file() and b'status: published' in path.read_bytes():
            result.append(path.resolve())
    return sorted(result)


def parse_manifest():
    assert MANIFEST_PATH.is_file(), f'Manifest file {MANIFEST_PATH} is missing.'
    lines = MANIFEST_PATH.read_text().strip().splitlines()
    entries = []
    for line in lines:
        parts = line.strip().split(maxsplit=1)
        assert len(parts) == 2, f"Invalid manifest line format: '{line}'"
        digest, filename = parts
        assert len(digest) == 64 and all(c in '0123456789abcdefABCDEF' for c in digest), \
            f"Invalid SHA-256 digest in manifest line: '{line}'"
        filename = filename.lstrip(' *')
        path = Path(filename)
        if not path.is_absolute():
            path = DOCS_DIR / path
        entries.append((path.resolve(), digest.lower(), filename))
    return lines, entries


def assert_manifest_matches_current_published():
    _, entries = parse_manifest()
    expected = published_markdown_files()
    listed = [path for path, _, _ in entries]
    assert len(listed) == len(set(listed)), 'Manifest contains duplicate file entries.'
    assert set(listed) == set(expected), \
        f'Manifest files differ from discovered published Markdown files: {listed} vs {expected}'
    for path, digest, _ in entries:
        assert path.is_file(), f'Manifest entry refers to missing file {path}'
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        assert digest == actual, f'Hash mismatch in manifest for {path.name}.'


def test_published_md_files_updated_and_content_preserved():
    for filename in ['intro.md', 'setup.md']:
        path = DOCS_DIR / filename
        assert path.is_file(), f'Expected file {path} is missing.'
        content = path.read_bytes()
        assert b'NovaBrand' in content, f"File {filename} should contain 'NovaBrand'."
        assert b'LegacyBrand' not in content, f"File {filename} should no longer contain 'LegacyBrand'."
        assert content == EXPECTED[filename], f'Unrelated content in {filename} was changed.'

    for path in published_markdown_files():
        assert b'LegacyBrand' not in path.read_bytes(), \
            f"Published Markdown file {path} still contains 'LegacyBrand'."


def test_draft_md_files_unchanged():
    path = DOCS_DIR / 'draft_api.md'
    assert path.is_file(), f'Expected file {path} is missing.'
    content = path.read_bytes()
    assert b'LegacyBrand' in content, "File draft_api.md should still contain 'LegacyBrand'."
    assert b'NovaBrand' not in content, "File draft_api.md should not contain 'NovaBrand'."
    assert content == EXPECTED['draft_api.md'], 'draft_api.md was otherwise modified.'


def test_non_md_files_unchanged():
    path = DOCS_DIR / 'notes.txt'
    assert path.is_file(), f'Expected file {path} is missing.'
    content = path.read_bytes()
    assert b'LegacyBrand' in content, "File notes.txt should still contain 'LegacyBrand'."
    assert b'NovaBrand' not in content, "File notes.txt should not contain 'NovaBrand'."
    assert content == EXPECTED['notes.txt'], 'notes.txt was otherwise modified.'


def test_manifest_exists_and_correct():
    lines, entries = parse_manifest()
    assert len(lines) == 2, f'Manifest should contain exactly 2 entries, found {len(lines)}.'
    by_basename = {path.name: digest for path, digest, _ in entries}
    for filename in ['intro.md', 'setup.md']:
        assert filename in by_basename, f'Manifest is missing entry for {filename}.'
        actual = hashlib.sha256((DOCS_DIR / filename).read_bytes()).hexdigest()
        assert by_basename[filename] == actual, f'Hash mismatch in manifest for {filename}.'
    assert_manifest_matches_current_published()


def candidate_scripts():
    excluded = {Path('/tmp/test_final_state.py').resolve()}
    found = []
    for root in [Path('/home/user'), Path('/tmp')]:
        if not root.exists():
            continue
        for path in root.rglob('*'):
            try:
                if not path.is_file() or path.resolve() in excluded:
                    continue
                if '/.cache/' in str(path) or '/__pycache__/' in str(path):
                    continue
                head = path.read_bytes()[:256]
                if path.suffix in {'.py', '.sh', '.bash'} or head.startswith(b'#!'):
                    found.append(path.resolve())
            except (OSError, PermissionError):
                pass
    return sorted(set(found), key=str)


def command_for(path, with_argument):
    if path.suffix == '.py':
        cmd = ['python3', str(path)]
    elif path.suffix in {'.sh', '.bash'}:
        cmd = ['bash', str(path)]
    elif os.access(path, os.X_OK):
        cmd = [str(path)]
    else:
        first = path.read_text(errors='ignore').splitlines()[0]
        assert first.startswith('#!')
        cmd = shlex.split(first[2:]) + [str(path)]
    if with_argument:
        cmd.append(str(DOCS_DIR))
    return cmd


def exercise_candidate(path, with_argument, backup):
    shutil.rmtree(DOCS_DIR)
    shutil.copytree(backup, DOCS_DIR)

    probe_dir = DOCS_DIR / '__verifier_probe__'
    probe_dir.mkdir()
    published = probe_dir / 'published.md'
    draft = probe_dir / 'draft.md'
    text = probe_dir / 'published.txt'
    published_original = b'header\nstatus: published\nLegacyBrand middle LegacyBrand\ntail\n'
    published_expected = published_original.replace(b'LegacyBrand', b'NovaBrand')
    draft_original = b'status: draft\nLegacyBrand must stay\n'
    text_original = b'status: published\nLegacyBrand must stay\n'
    published.write_bytes(published_original)
    draft.write_bytes(draft_original)
    text.write_bytes(text_original)

    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
    assert fd >= 0
    IN_MOVED_FROM = 0x00000040
    IN_MOVED_TO = 0x00000080
    wd = libc.inotify_add_watch(fd, os.fsencode(probe_dir), IN_MOVED_FROM | IN_MOVED_TO)
    assert wd >= 0

    env = os.environ.copy()
    env['DOCS_DIR'] = str(DOCS_DIR)
    try:
        result = subprocess.run(command_for(path, with_argument), cwd=str(path.parent), env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
        if result.returncode != 0:
            return False, f'exited {result.returncode}'

        raw = b''
        while True:
            try:
                chunk = os.read(fd, 65536)
                if not chunk:
                    break
                raw += chunk
            except BlockingIOError:
                break

        events = []
        offset = 0
        while offset + 16 <= len(raw):
            _, mask, cookie, name_len = struct.unpack_from('iIII', raw, offset)
            offset += 16
            name = raw[offset:offset + name_len].split(b'\0', 1)[0].decode(errors='replace')
            offset += name_len
            events.append((mask, cookie, name))

        moved_to = {(cookie, name) for mask, cookie, name in events if mask & IN_MOVED_TO}
        same_dir_atomic = any(
            (mask & IN_MOVED_FROM) and name != 'published.md' and (cookie, 'published.md') in moved_to
            for mask, cookie, name in events
        )

        if published.read_bytes() != published_expected:
            return False, 'did not preserve and replace all content in the published probe'
        if draft.read_bytes() != draft_original or text.read_bytes() != text_original:
            return False, 'modified an ineligible probe file'
        if not same_dir_atomic:
            return False, 'did not rename a temporary file from the same directory over the probe'
        assert_manifest_matches_current_published()
        return True, ''
    except Exception as exc:
        return False, str(exc)
    finally:
        os.close(fd)


def test_update_script_is_present_functional_and_atomic():
    scripts = candidate_scripts()
    assert scripts, 'No update script was left for verification.'
    parent = Path(tempfile.mkdtemp(prefix='docs-verifier-'))
    backup = parent / 'docs'
    shutil.copytree(DOCS_DIR, backup)
    failures = []
    try:
        for script in scripts:
            for with_argument in (False, True):
                ok, reason = exercise_candidate(script, with_argument, backup)
                if ok:
                    return
                failures.append(f'{script} ({"with docs argument" if with_argument else "without argument"}): {reason}')
        assert False, 'No submitted script performed the required atomic update. ' + '; '.join(failures)
    finally:
        shutil.rmtree(DOCS_DIR, ignore_errors=True)
        shutil.copytree(backup, DOCS_DIR)
        shutil.rmtree(parent, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
