#!/bin/bash
mkdir -p /logs/verifier
ok=1

cat <<'PY' > /tmp/prepare_verifier_inputs.py
import io
import json
import os
import pathlib
import secrets
import shutil
import subprocess
import tarfile

home = pathlib.Path('/home/user')
incoming = home / 'incoming'
extracted = home / 'extracted'

shutil.rmtree(incoming, ignore_errors=True)
shutil.rmtree(extracted, ignore_errors=True)
incoming.mkdir(parents=True)
extracted.mkdir(parents=True)
for path in (home / 'quarantine.log', home / 'elf_manifest.txt'):
    try:
        path.unlink()
    except FileNotFoundError:
        pass

def compile_binary(source, output):
    pathlib.Path(source).write_text('#include <stdio.h>\nint main(void) { puts("verifier ELF"); return 0; }\n')
    subprocess.run(['gcc', source, '-o', output], check=True)

# Recreate the original fixtures so the submitted script is tested from a clean state.
compile_binary('/tmp/main1.c', '/tmp/safe_bin_alpha')
compile_binary('/tmp/main2.c', '/tmp/safe_bin_beta')
compile_binary('/tmp/main3.c', '/tmp/bad_bin')
pathlib.Path('/tmp/readme.txt').write_text('Just a text file\n')

with tarfile.open(incoming / 'build_1.tar.gz', 'w:gz') as archive:
    archive.add('/tmp/safe_bin_alpha', arcname='safe_bin_alpha')
    archive.add('/tmp/readme.txt', arcname='readme.txt')
with tarfile.open(incoming / 'build_2.tar.gz', 'w:gz') as archive:
    archive.add('/tmp/safe_bin_beta', arcname='nested/safe_bin_beta')

def add_bytes(archive, name, data):
    info = tarfile.TarInfo(name=name)
    info.size = len(data)
    archive.addfile(info, io.BytesIO(data))

with tarfile.open(incoming / 'malicious_absolute.tar.gz', 'w:gz') as archive:
    archive.add('/tmp/bad_bin', arcname='/tmp/bad_bin')
with tarfile.open(incoming / 'malicious_relative.tar.gz', 'w:gz') as archive:
    add_bytes(archive, '../sneaky_overwrite.txt', b'hacked file!')

token = secrets.token_hex(12)
dynamic_bin_name = 'verify_bin_' + token
dynamic_bin = '/tmp/' + dynamic_bin_name
compile_binary('/tmp/verify_' + token + '.c', dynamic_bin)
dynamic_text_name = 'verify_note_' + token + '.txt'
pathlib.Path('/tmp/' + dynamic_text_name).write_text('dynamic safe payload ' + token + '\n')
safe_archive = 'verify_safe_' + token + '.tar.gz'
with tarfile.open(incoming / safe_archive, 'w:gz') as archive:
    archive.add(dynamic_bin, arcname='dynamic/' + dynamic_bin_name)
    archive.add('/tmp/' + dynamic_text_name, arcname=dynamic_text_name)

abs_archive = 'verify_abs_' + token + '.tar.gz'
rel_archive = 'verify_rel_' + token + '.tar.gz'
abs_escape = '/tmp/verifier_abs_escape_' + token
rel_escape = '/home/user/verifier_rel_escape_' + token
compromised_abs_member = 'must_not_extract_abs_' + token + '.txt'
compromised_rel_member = 'must_not_extract_rel_' + token + '.txt'
for path in (abs_escape, rel_escape):
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass

with tarfile.open(incoming / abs_archive, 'w:gz') as archive:
    add_bytes(archive, abs_escape, b'absolute escape')
    add_bytes(archive, compromised_abs_member, b'archive must be wholly rejected')
with tarfile.open(incoming / rel_archive, 'w:gz') as archive:
    add_bytes(archive, '../verifier_rel_escape_' + token, b'relative escape')
    add_bytes(archive, compromised_rel_member, b'archive must be wholly rejected')

metadata = {
    'dynamic_bin_name': dynamic_bin_name,
    'dynamic_bin_source': dynamic_bin,
    'dynamic_text_name': dynamic_text_name,
    'dynamic_text_content': 'dynamic safe payload ' + token,
    'quarantined': [
        'malicious_absolute.tar.gz',
        'malicious_relative.tar.gz',
        abs_archive,
        rel_archive,
    ],
    'abs_escape': abs_escape,
    'rel_escape': rel_escape,
    'compromised_members': [compromised_abs_member, compromised_rel_member],
}
pathlib.Path('/tmp/verifier_meta.json').write_text(json.dumps(metadata))
PY

python3 /tmp/prepare_verifier_inputs.py || ok=0

if [ "$ok" -eq 1 ]; then
    if [ ! -f /home/user/process_builds.sh ]; then
        echo 'Missing /home/user/process_builds.sh'
        ok=0
    elif ! bash -n /home/user/process_builds.sh; then
        echo 'process_builds.sh is not valid Bash syntax'
        ok=0
    elif ! timeout 30s bash /home/user/process_builds.sh; then
        echo 'process_builds.sh failed or timed out'
        ok=0
    fi
fi

cat <<'PY' > /tmp/test_final_state.py
import hashlib
import json
import os
import subprocess

with open('/tmp/verifier_meta.json') as f:
    META = json.load(f)

def get_elf_entry_point(filepath):
    result = subprocess.run(['readelf', '-h', filepath], capture_output=True, text=True)
    assert result.returncode == 0, f'Failed to run readelf on {filepath}'
    for line in result.stdout.splitlines():
        if 'Entry point address:' in line:
            parts = line.split(':')
            if len(parts) == 2:
                return parts[1].strip()
    return None

def get_sha256(filepath):
    digest = hashlib.sha256()
    with open(filepath, 'rb') as f:
        for block in iter(lambda: f.read(4096), b''):
            digest.update(block)
    return digest.hexdigest()

def test_quarantine_log():
    quarantine_log = '/home/user/quarantine.log'
    assert os.path.exists(quarantine_log), f'{quarantine_log} does not exist.'
    with open(quarantine_log) as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_quarantined = set(META['quarantined'])
    actual_quarantined = set(lines)
    missing = expected_quarantined - actual_quarantined
    extra = actual_quarantined - expected_quarantined
    assert not missing, f'Missing expected archives in quarantine log: {missing}'
    assert not extra, f'Found extra archives in quarantine log that should be safe: {extra}'

def test_extracted_files_exist():
    expected_files = [
        '/home/user/extracted/safe_bin_alpha',
        '/home/user/extracted/readme.txt',
        '/home/user/extracted/nested/safe_bin_beta',
        '/home/user/extracted/dynamic/' + META['dynamic_bin_name'],
        '/home/user/extracted/' + META['dynamic_text_name'],
    ]
    for fpath in expected_files:
        assert os.path.isfile(fpath), f'Expected extracted file {fpath} is missing.'
    with open('/home/user/extracted/' + META['dynamic_text_name']) as f:
        assert f.read().strip() == META['dynamic_text_content']

def test_compromised_archives_were_not_extracted():
    assert not os.path.exists(META['abs_escape']), 'Absolute-path archive escaped extraction directory.'
    assert not os.path.exists(META['rel_escape']), 'Traversal archive escaped extraction directory.'
    for member in META['compromised_members']:
        assert not os.path.exists('/home/user/extracted/' + member), \
            'A benign-looking member of a compromised archive was extracted.'
    assert not os.path.exists('/home/user/extracted/tmp/bad_bin')

def test_elf_manifest():
    manifest = '/home/user/elf_manifest.txt'
    assert os.path.exists(manifest), f'{manifest} does not exist.'

    safe_binaries = [
        '/tmp/safe_bin_alpha',
        '/tmp/safe_bin_beta',
        META['dynamic_bin_source'],
    ]
    expected_lines = []
    for bin_path in safe_binaries:
        assert os.path.exists(bin_path), f'Original binary {bin_path} missing from /tmp.'
        sha = get_sha256(bin_path)
        base = os.path.basename(bin_path)
        entry = get_elf_entry_point(bin_path)
        assert entry is not None, f'Could not determine entry point for {bin_path}'
        expected_lines.append(f'{sha} {base} {entry}')
    expected_lines.sort(key=lambda line: line.split()[1])

    with open(manifest) as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert len(actual_lines) == len(expected_lines), \
        f'Expected {len(expected_lines)} lines in manifest, got {len(actual_lines)}.'
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, \
            f'Line {i + 1} mismatch in manifest.\nExpected: {expected}\nActual:   {actual}'
PY

if [ "$ok" -eq 1 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
