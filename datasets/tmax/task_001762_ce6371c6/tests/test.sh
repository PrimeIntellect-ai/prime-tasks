#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import random
import re
import subprocess

BASE_DIR = '/home/user/legacy_configs'
MANIFEST_PATH = '/home/user/update_manifest.csv'
OLD = 'db_pool_size=10'
NEW = 'db_pool_size=50'


def original_contents():
    expected = {}
    random.seed(42)
    for i in range(500):
        rel = f'group_{i % 10}/config_{i}.ini'
        has_target = random.random() < 0.8
        content = '[database]\n'
        if has_target:
            content += 'db_pool_size=10\nhost=db.internal\n'
        else:
            content += 'db_pool_size=20\nhost=db.internal\n'
        expected[rel] = content
    return expected


def find_migration_script():
    candidates = []
    excluded = {'/tmp/test_final_state.py'}
    for search_root in ('/home/user', '/app', '/root', '/tmp'):
        if not os.path.isdir(search_root):
            continue
        for root, dirs, files in os.walk(search_root):
            dirs[:] = [d for d in dirs if d not in {'.cache', '__pycache__', '.pytest_cache'}]
            for name in files:
                if not name.endswith('.py'):
                    continue
                path = os.path.join(root, name)
                if path in excluded or os.path.islink(path):
                    continue
                try:
                    if os.path.getsize(path) > 1024 * 1024:
                        continue
                    with open(path, 'r', encoding='utf-8') as f:
                        source = f.read()
                except (OSError, UnicodeError):
                    continue
                if 'legacy_configs' not in source or 'update_manifest' not in source:
                    continue

                # Include local helper modules when checking the implementation.
                bundle = source
                try:
                    for sibling in os.listdir(root):
                        sibling_path = os.path.join(root, sibling)
                        if sibling.endswith('.py') and sibling_path != path and not os.path.islink(sibling_path):
                            with open(sibling_path, 'r', encoding='utf-8') as f:
                                bundle += '\n' + f.read()
                except (OSError, UnicodeError):
                    pass

                concurrent = re.search(
                    r'concurrent\s*\.\s*futures|multiprocessing|ProcessPoolExecutor|ThreadPoolExecutor|\bPool\s*\(|\bthreading\b',
                    bundle,
                )
                locking_module = re.search(r'\bfcntl\b|\bportalocker\b|\bfilelock\b', bundle)
                locking_call = re.search(r'\bflock\s*\(|\blockf\s*\(|\bFileLock\s*\(|portalocker\s*\.\s*lock', bundle)
                if concurrent and locking_module and locking_call:
                    candidates.append(path)

    assert candidates, 'No Python migration script using concurrency and file locking was found.'
    candidates.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return candidates[0]


def test_migration_script_and_final_state():
    originals = original_contents()
    expected_paths = set(originals)

    actual_paths = set()
    for root, _, files in os.walk(BASE_DIR):
        for name in files:
            if name.endswith('.ini'):
                full_path = os.path.join(root, name)
                assert not os.path.islink(full_path), f'Configuration file must not be a symlink: {full_path}'
                actual_paths.add(os.path.relpath(full_path, BASE_DIR))
    assert actual_paths == expected_paths, 'The original configuration file set was altered.'

    script = find_migration_script()

    # Restore the known initial fixture, then execute the submitted artifact. This
    # prevents a manifest for hypothetical replacements from passing verification.
    for rel, content in originals.items():
        full_path = os.path.join(BASE_DIR, rel)
        with open(full_path, 'w', encoding='utf-8', newline='') as f:
            f.write(content)
    if os.path.lexists(MANIFEST_PATH):
        assert not os.path.isdir(MANIFEST_PATH), 'Manifest path is a directory.'
        os.unlink(MANIFEST_PATH)

    result = subprocess.run(
        ['python3', script],
        cwd=os.path.dirname(script) or '/',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=120,
    )
    assert result.returncode == 0, f'Migration script failed:\n{result.stdout}'

    expected_manifest = set()
    for rel, original in originals.items():
        expected_content = original.replace(OLD, NEW)
        full_path = os.path.join(BASE_DIR, rel)
        assert os.path.isfile(full_path), f'Missing configuration file: {rel}'
        with open(full_path, 'r', encoding='utf-8', newline='') as f:
            actual_content = f.read()
        assert actual_content == expected_content, f'Configuration file was not migrated correctly: {rel}'
        checksum = hashlib.sha256(expected_content.encode('utf-8')).hexdigest()
        expected_manifest.add(f'{rel},{checksum}')

    assert os.path.isfile(MANIFEST_PATH), f'Manifest file {MANIFEST_PATH} is missing.'
    with open(MANIFEST_PATH, 'r', encoding='utf-8') as f:
        lines = [line.strip() for line in f if line.strip()]

    for line in lines:
        assert re.fullmatch(r'[^,]+,[0-9a-f]{64}', line), f'Invalid manifest line: {line!r}'
    assert len(lines) == len(set(lines)), 'Manifest contains duplicate entries.'
    agent_manifest = set(lines)

    # Preserve the original manifest-similarity assertion.
    recomputed_expected_manifest = set()
    for root, _, files in os.walk(BASE_DIR):
        for file in files:
            if file.endswith('.ini'):
                full_path = os.path.join(root, file)
                with open(full_path, 'r') as f:
                    content = f.read()
                expected_content = content.replace(OLD, NEW)
                h = hashlib.sha256(expected_content.encode('utf-8')).hexdigest()
                rel_path = os.path.relpath(full_path, BASE_DIR)
                recomputed_expected_manifest.add(f'{rel_path},{h}')

    if not recomputed_expected_manifest and not agent_manifest:
        similarity = 0.0
    else:
        intersection = len(recomputed_expected_manifest.intersection(agent_manifest))
        union = len(recomputed_expected_manifest.union(agent_manifest))
        similarity = intersection / union
    assert similarity >= 0.95, (
        f'Manifest similarity {similarity} is below threshold 0.95. '
        f'Expected {len(recomputed_expected_manifest)} entries, got {len(agent_manifest)}.'
    )

    assert agent_manifest == expected_manifest, 'Manifest does not exactly describe all migrated files.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
