#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
import time


def read_config():
    config = {}
    with open('/home/user/doc_rules.ini', 'r', encoding='utf-8') as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith('#'):
                continue
            key, value = line.split('=', 1)
            config[key.strip()] = value.strip()
    assert set(config) >= {'Incoming', 'Processed', 'Archives', 'Snapshot'}
    return config


def normalized(name):
    while name.startswith('./'):
        name = name[2:]
    return name.rstrip('/')


def expected_conversions():
    cfg = read_config()
    expected = {}
    archive_count = 0
    for entry in sorted(os.listdir(cfg['Incoming'])):
        path = os.path.join(cfg['Incoming'], entry)
        if not os.path.isfile(path):
            continue
        archive_count += 1
        assert tarfile.is_tarfile(path), f'{path} is not a readable tar or tar.gz archive.'
        with tarfile.open(path, 'r:*') as archive:
            for member in archive.getmembers():
                if member.isfile() and member.name.endswith('.md'):
                    source = archive.extractfile(member).read()
                    converted = re.sub(br'(?m)^# ', b'HEADER: ', source)
                    relative = normalized(member.name)
                    assert relative and not relative.startswith('../')
                    expected[relative[:-3] + '.txt'] = converted
    assert archive_count > 0, 'No incoming archives were found.'
    assert expected, 'No Markdown inputs were found in the incoming archives.'
    return expected


def regular_members(path):
    with tarfile.open(path, 'r:') as archive:
        return [(normalized(m.name), archive.extractfile(m).read())
                for m in archive.getmembers() if m.isfile()]


def find_suffix(members, suffix):
    matches = [data for name, data in members
               if name == suffix or name.endswith('/' + suffix)]
    assert len(matches) == 1, f'Expected exactly one archived regular file ending in {suffix}, found {len(matches)}.'
    return matches[0]


# Preserve the original verifier's assertions.
def test_directories_exist():
    assert os.path.isdir('/home/user/incoming'), '/home/user/incoming is missing.'
    assert os.path.isdir('/home/user/processed'), '/home/user/processed is missing.'
    assert os.path.isdir('/home/user/archives'), '/home/user/archives is missing.'


def test_converted_files_exist_and_correct_content():
    intro_txt = '/home/user/processed/intro.txt'
    conclusion_txt = '/home/user/processed/conclusion.txt'
    assert os.path.isfile(intro_txt), f'{intro_txt} is missing.'
    assert os.path.isfile(conclusion_txt), f'{conclusion_txt} is missing.'
    with open(intro_txt, 'r') as f:
        intro_content = f.read()
    assert 'HEADER: Introduction' in intro_content
    assert 'Welcome to the docs.' in intro_content
    with open(conclusion_txt, 'r') as f:
        conclusion_content = f.read()
    assert 'HEADER: Conclusion' in conclusion_content
    assert 'End of docs.' in conclusion_content


def test_original_md_files_deleted():
    assert not os.path.exists('/home/user/processed/intro.md')
    assert not os.path.exists('/home/user/processed/conclusion.md')


def test_changelog_exists():
    changelog = '/home/user/processed/changelog.txt'
    assert os.path.isfile(changelog)
    with open(changelog, 'r') as f:
        assert f.read().strip() == 'NEW UPDATE'


def test_backup_0_tar():
    path = '/home/user/archives/backup_0.tar'
    assert os.path.isfile(path)
    with tarfile.open(path, 'r') as archive:
        names = archive.getnames()
        assert any(name.endswith('intro.txt') for name in names)
        assert any(name.endswith('conclusion.txt') for name in names)
        assert not any(name.endswith('changelog.txt') for name in names)


def test_backup_1_tar():
    path = '/home/user/archives/backup_1.tar'
    assert os.path.isfile(path)
    with tarfile.open(path, 'r') as archive:
        names = archive.getnames()
        assert any(name.endswith('changelog.txt') for name in names)
        for member in archive.getmembers():
            if member.name.endswith('intro.txt') or member.name.endswith('conclusion.txt'):
                assert not member.isfile()


def test_snapshot_file_exists():
    assert os.path.isfile('/home/user/archives/backup.snar')


# General checks derived from the configuration and every incoming archive.
def test_configuration_paths_and_all_conversions():
    cfg = read_config()
    assert cfg == {
        'Incoming': '/home/user/incoming',
        'Processed': '/home/user/processed',
        'Archives': '/home/user/archives',
        'Snapshot': '/home/user/archives/backup.snar',
    }
    for path in (cfg['Incoming'], cfg['Processed'], cfg['Archives']):
        assert os.path.isdir(path)

    expected = expected_conversions()
    for relative, content in expected.items():
        output = os.path.join(cfg['Processed'], relative)
        assert os.path.isfile(output), f'Missing converted output {output}.'
        with open(output, 'rb') as f:
            assert f.read() == content, f'Incorrect conversion in {output}.'

    for root, _, files in os.walk(cfg['Processed']):
        assert not any(name.endswith('.md') for name in files), f'Markdown remains under {root}.'


def test_backups_match_all_archive_derived_outputs():
    cfg = read_config()
    expected = expected_conversions()
    backup0 = os.path.join(cfg['Archives'], 'backup_0.tar')
    backup1 = os.path.join(cfg['Archives'], 'backup_1.tar')

    members0 = regular_members(backup0)
    for relative, content in expected.items():
        assert find_suffix(members0, relative) == content
    assert not any(name == 'changelog.txt' or name.endswith('/changelog.txt') for name, _ in members0)

    members1 = regular_members(backup1)
    assert len(members1) == 1, 'The level-1 archive contains regular files other than changelog.txt.'
    name, content = members1[0]
    assert name == 'changelog.txt' or name.endswith('/changelog.txt')
    assert content.strip() == b'NEW UPDATE'


def test_gnu_incremental_metadata_and_snapshot_are_real_and_reusable():
    cfg = read_config()
    backup0 = os.path.join(cfg['Archives'], 'backup_0.tar')
    backup1 = os.path.join(cfg['Archives'], 'backup_1.tar')
    snapshot = cfg['Snapshot']

    for backup in (backup0, backup1):
        with tarfile.open(backup, 'r:') as archive:
            assert any(member.type == tarfile.GNUTYPE_DUMPDIR for member in archive.getmembers()), \
                f'{backup} lacks GNU incremental directory metadata.'

    with open(snapshot, 'rb') as f:
        assert f.read(32).startswith(b'GNU tar-'), 'Snapshot is not GNU tar incremental metadata.'

    with tarfile.open(backup1, 'r:') as archive:
        changelog_members = [normalized(m.name) for m in archive.getmembers()
                             if m.isfile() and normalized(m.name).endswith('changelog.txt')]
    assert len(changelog_members) == 1
    parent = os.path.dirname(changelog_members[0])
    if parent == '':
        cwd, source = cfg['Processed'], '.'
    elif parent == 'processed':
        cwd, source = os.path.dirname(cfg['Processed']), 'processed'
    elif parent == 'home/user/processed':
        cwd, source = '/', cfg['Processed']
    else:
        cwd, source = '/', cfg['Processed']

    tempdir = tempfile.mkdtemp(prefix='incremental-check-', dir='/tmp')
    copied_snapshot = os.path.join(tempdir, 'state.snar')
    probe_tar = os.path.join(tempdir, 'probe.tar')
    probe_name = '.__verifier_incremental_probe__.txt'
    probe_path = os.path.join(cfg['Processed'], probe_name)
    shutil.copy2(snapshot, copied_snapshot)
    try:
        time.sleep(1.1)
        with open(probe_path, 'wb') as f:
            f.write(b'incremental probe\n')
        result = subprocess.run(
            ['tar', '--listed-incremental=' + copied_snapshot, '-cf', probe_tar, source],
            cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        assert result.returncode == 0, 'GNU tar could not reuse the submitted snapshot: ' + result.stderr
        probe_members = regular_members(probe_tar)
        assert len(probe_members) == 1, 'Snapshot does not describe the current backed-up state.'
        assert probe_members[0][0].endswith(probe_name)
        assert probe_members[0][1] == b'incremental probe\n'
    finally:
        if os.path.exists(probe_path):
            os.unlink(probe_path)
        shutil.rmtree(tempdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
