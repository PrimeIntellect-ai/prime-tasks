#!/bin/bash
mkdir -p /logs/verifier
reward=0

cat > /tmp/verify_doc_processor.py <<'PY'
import collections
import json
import os
import pathlib
import pwd
import secrets
import shutil
import subprocess
import tarfile
import zipfile

WORKSPACE = pathlib.Path('/home/user/workspace')
PROJECT = WORKSPACE / 'doc_processor'
MANIFEST = PROJECT / 'Cargo.toml'
ARCHIVE = WORKSPACE / 'legacy_docs.zip'
EXTRACTED = WORKSPACE / 'extracted_docs'
LOG = WORKSPACE / 'extraction_log.txt'
TAR = WORKSPACE / 'clean_docs.tar.gz'


def remove_path(path):
    path = pathlib.Path(path)
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def converted(text):
    lines = []
    for line in text.split('\n'):
        if line.startswith('[HEADER] '):
            line = '# ' + line[len('[HEADER] '):]
        lines.append(line.replace('[B]', '**').replace('[/B]', '**'))
    return '\n'.join(lines)


# Require and build an actual Rust binary before creating the unpredictable fixture.
assert PROJECT.is_dir(), f'Rust project missing at {PROJECT}'
assert MANIFEST.is_file() and not MANIFEST.is_symlink(), f'Cargo.toml missing at {MANIFEST}'
assert shutil.which('cargo'), 'cargo is unavailable'

build = subprocess.run(
    ['cargo', 'build', '--manifest-path', str(MANIFEST)],
    cwd=PROJECT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    timeout=300,
)
assert build.returncode == 0, 'Rust project did not build:\n' + build.stdout[-8000:]

meta_run = subprocess.run(
    ['cargo', 'metadata', '--no-deps', '--format-version', '1', '--manifest-path', str(MANIFEST)],
    cwd=PROJECT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    timeout=60,
)
assert meta_run.returncode == 0, 'Could not inspect Rust project:\n' + meta_run.stdout[-4000:]
metadata = json.loads(meta_run.stdout)
manifest_real = MANIFEST.resolve()
packages = [p for p in metadata['packages'] if pathlib.Path(p['manifest_path']).resolve() == manifest_real]
assert packages, 'Cargo.toml does not define a Rust package'
package = packages[0]
bins = [t for t in package['targets'] if 'bin' in t.get('kind', [])]
assert bins, 'The Rust project has no executable binary target'
if len(bins) == 1:
    binary_target = bins[0]
else:
    default_name = package.get('default_run')
    matches = [t for t in bins if t['name'] == default_name]
    assert len(matches) == 1, 'Multiple binaries exist without an unambiguous default-run target'
    binary_target = matches[0]
binary = pathlib.Path(metadata['target_directory']) / 'debug' / binary_target['name']
assert binary.is_file() and os.access(binary, os.X_OK), f'Built Rust executable missing at {binary}'

nonce = secrets.token_hex(10)
safe_inputs = {
    'docs/intro.txt': '[HEADER] Introduction\nThis is [B]very[/B] important.\n' + nonce,
    'docs/setup.txt': '[HEADER] Setup\nFollow the [B]instructions[/B].\n' + nonce[::-1],
    f'docs/deep_{nonce[:8]}/notes_{nonce[8:16]}.txt': '[HEADER] Dynamic Notes\n[B]alpha[/B] and [B]beta[/B]\n' + nonce,
    f'appendix_{nonce[2:10]}.txt': '[HEADER] Appendix\nToken: [B]' + nonce + '[/B]',
}
malicious = {
    '../secret_config.txt': 'MALICIOUS CONTENT ' + nonce,
    f'../escape_{nonce}.txt': 'ESCAPE ' + nonce,
    f'../../outside_{nonce}.txt': 'OUTSIDE ' + nonce,
    f'docs/../blocked_{nonce}.txt': 'BLOCKED ' + nonce,
}

# Remove all prior claimed results, then install a fresh randomized archive.
for path in (ARCHIVE, EXTRACTED, LOG, TAR):
    remove_path(path)
ARCHIVE.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(ARCHIVE, 'w', compression=zipfile.ZIP_DEFLATED) as zf:
    for name, body in safe_inputs.items():
        zf.writestr(name, body)
    for name, body in malicious.items():
        zf.writestr(name, body)

# Sentinels prove traversal entries did not overwrite files outside extraction.
outside_targets = {
    WORKSPACE / 'secret_config.txt': 'SAFE SECRET ' + nonce,
    WORKSPACE / f'escape_{nonce}.txt': 'SAFE ESCAPE ' + nonce,
    pathlib.Path('/home/user') / f'outside_{nonce}.txt': 'SAFE OUTSIDE ' + nonce,
}
for path, body in outside_targets.items():
    remove_path(path)
    path.write_text(body, encoding='utf-8')
    path.chmod(0o666)

# Execute the already-built Rust artifact as the workspace user. Building occurred
# before fixture creation, so build scripts cannot fabricate the tested outputs.
user = pwd.getpwnam('user')
def demote():
    os.setgroups([])
    os.setgid(user.pw_gid)
    os.setuid(user.pw_uid)

env = os.environ.copy()
env['HOME'] = user.pw_dir
run = subprocess.run(
    [str(binary)], cwd=PROJECT, env=env, preexec_fn=demote,
    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    timeout=120,
)
assert run.returncode == 0, 'Rust executable failed:\n' + run.stdout[-8000:]

# Preserve and strengthen the original log assertions.
assert LOG.is_file() and not LOG.is_symlink(), f'Log file missing at {LOG}'
log_lines = LOG.read_text(encoding='utf-8').splitlines()
expected_log = [f'EXTRACTED: {name}' for name in safe_inputs]
expected_log += [f'SKIPPED: {name}' for name in malicious]
assert collections.Counter(log_lines) == collections.Counter(expected_log), (
    f'Extraction log was inaccurate. Expected {expected_log!r}, got {log_lines!r}'
)

# No traversal target may have been changed, including the original secret path.
for path, body in outside_targets.items():
    assert path.is_file() and not path.is_symlink(), f'Traversal altered or removed {path}'
    assert path.read_text(encoding='utf-8') == body, f'Traversal overwrote {path}'
blocked_base = EXTRACTED / f'blocked_{nonce}'
assert not blocked_base.with_suffix('.txt').exists(), 'docs/../ traversal entry was extracted'
assert not blocked_base.with_suffix('.md').exists(), 'docs/../ traversal entry was converted'

expected_md = {str(pathlib.PurePosixPath(name).with_suffix('.md')): converted(body)
               for name, body in safe_inputs.items()}

# Converted files must exist in extracted_docs, have exact converted contents,
# and all legacy .txt files must be gone.
assert EXTRACTED.is_dir() and not EXTRACTED.is_symlink(), 'extracted_docs directory missing'
actual_extracted = {}
for root, dirs, files in os.walk(EXTRACTED):
    for filename in files:
        path = pathlib.Path(root) / filename
        rel = path.relative_to(EXTRACTED).as_posix()
        assert not filename.endswith('.txt'), f'Legacy text file was not deleted: {rel}'
        assert path.is_file() and not path.is_symlink(), f'Unexpected extracted artifact: {rel}'
        actual_extracted[rel] = path.read_text(encoding='utf-8')
assert actual_extracted == expected_md, 'Extracted Markdown files or their contents are incorrect'

# Preserve the original tar validity, structure, exclusion, and conversion checks,
# while checking every randomized input rather than only docs/intro.md.
assert TAR.is_file() and not TAR.is_symlink(), f'Output tarball missing at {TAR}'
with TAR.open('rb') as f:
    assert f.read(2) == b'\x1f\x8b', 'clean_docs.tar.gz is not gzip-compressed'
assert tarfile.is_tarfile(TAR), f'{TAR} is not a valid tar archive'

with tarfile.open(TAR, 'r:gz') as tf:
    archived = {}
    for member in tf.getmembers():
        name = member.name
        while name.startswith('./'):
            name = name[2:]
        pure = pathlib.PurePosixPath(name)
        assert not pure.is_absolute() and '..' not in pure.parts, f'Unsafe path in output tar: {member.name}'
        if member.isdir():
            continue
        assert member.isfile(), f'Non-file artifact in output tar: {member.name}'
        assert name.endswith('.md'), f'Legacy or non-Markdown file in output tar: {member.name}'
        assert 'secret_config' not in name, 'Malicious file was included in output tar'
        stream = tf.extractfile(member)
        assert stream is not None, f'Could not read {member.name}'
        archived[name] = stream.read().decode('utf-8')

assert archived == expected_md, 'Tar structure or converted file contents are incorrect'
intro = archived['docs/intro.md']
assert '# Introduction' in intro
assert '**very**' in intro
assert '[HEADER]' not in intro and '[B]' not in intro and '[/B]' not in intro
assert archived['docs/setup.md'] == expected_md['docs/setup.md']
PY

if python3 /tmp/verify_doc_processor.py; then
    reward=1
fi
printf '%s\n' "$reward" > /logs/verifier/reward.txt
exit 0
