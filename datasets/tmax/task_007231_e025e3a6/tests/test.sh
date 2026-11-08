#!/bin/bash
mkdir -p /logs/verifier
reward=0

# Recreate the specified input so cleanup.sh is exercised on a known, unmodified
# archive and configuration rather than merely grading pre-fabricated output.
if python3 - <<'PREP_EOF'
import io
import os
import tarfile

members = {
    'deep/nested/dir/access.log': b'''User login from 192.168.1.100\nFailed attempt from 10.0.0.5\nSuccess from 127.0.0.1\nSystem check complete.\n''',
    'server.log': b'''Line 1: 192.168.1.1\nLine 2: data\nLine 3: data\nLine 4: 10.10.10.10\nLine 5: data\nLine 6: data\nLine 7: 172.16.0.1\nLine 8: end\n''',
    '../../home/user/data.csv': b'''id,name,ip\n1,alice,192.168.1.50\n2,bob,10.0.0.200\n3,charlie,172.16.5.5\n''',
}

os.makedirs('/home/user/incoming', exist_ok=True)
with open('/home/user/admin.conf', 'w') as f:
    f.write('USER_ID=storage_admin\n')
    f.write(r'REDACT_PATTERN=[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' + '\n')
    f.write('SPLIT_LINES=5\n')
    f.write('MAX_STORAGE=100G\n')

with tarfile.open('/home/user/incoming/logs.tar.gz', 'w:gz') as tar:
    for name, data in members.items():
        info = tarfile.TarInfo(name)
        info.size = len(data)
        info.mode = 0o644
        tar.addfile(info, io.BytesIO(data))

uid = __import__('pwd').getpwnam('user').pw_uid
gid = __import__('pwd').getpwnam('user').pw_gid
for path in ['/home/user/admin.conf', '/home/user/incoming', '/home/user/incoming/logs.tar.gz']:
    os.chown(path, uid, gid)
PREP_EOF
then
    if [ -f /home/user/cleanup.sh ] && [ ! -L /home/user/cleanup.sh ]; then
        rm -rf /home/user/safe_zone
        mkdir -p /home/user/safe_zone
        rm -f /home/user/clean_logs.tar.bz2 /home/user/data.csv
        chown user:user /home/user/safe_zone
        chmod 777 /home/user/safe_zone

        if timeout 30s runuser -u user -- /bin/bash -c 'cd /home/user && /bin/bash /home/user/cleanup.sh'; then
            cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import posixpath
import subprocess
import tarfile
import tempfile
import pytest

ARCHIVE = '/home/user/clean_logs.tar.bz2'
SOURCE_MEMBERS = {
    'deep/nested/dir/access.log': b'''User login from 192.168.1.100\nFailed attempt from 10.0.0.5\nSuccess from 127.0.0.1\nSystem check complete.\n''',
    'server.log': b'''Line 1: 192.168.1.1\nLine 2: data\nLine 3: data\nLine 4: 10.10.10.10\nLine 5: data\nLine 6: data\nLine 7: 172.16.0.1\nLine 8: end\n''',
    '../../home/user/data.csv': b'''id,name,ip\n1,alice,192.168.1.50\n2,bob,10.0.0.200\n3,charlie,172.16.5.5\n''',
}
REDACT_PATTERN = r'[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}'
SPLIT_LINES = 5


def expected_files():
    flattened = {}
    for member_name, content in SOURCE_MEMBERS.items():
        name = posixpath.basename(member_name)
        assert name not in flattened, 'Fixture contains a basename collision'
        if name.endswith('.csv'):
            name = name[:-4] + '.tsv'
            content = content.replace(b',', b'\t')
        content = subprocess.run(
            ['sed', 's/' + REDACT_PATTERN + '/***/g'],
            input=content,
            stdout=subprocess.PIPE,
            check=True,
        ).stdout
        flattened[name] = content

    result = {}
    for name, content in flattened.items():
        lines = content.splitlines(keepends=True)
        if len(lines) > SPLIT_LINES:
            for index in range(0, len(lines), SPLIT_LINES):
                chunk_number = index // SPLIT_LINES
                suffix = chr(ord('a') + chunk_number // 26) + chr(ord('a') + chunk_number % 26)
                result[name + '.part' + suffix] = b''.join(lines[index:index + SPLIT_LINES])
        else:
            result[name] = content
    return result


def normalized_member_name(name):
    while name.startswith('./'):
        name = name[2:]
    return name.rstrip('/')


def read_and_validate_archive():
    files = {}
    layout = set()
    with tarfile.open(ARCHIVE, 'r:bz2') as tar:
        for member in tar.getmembers():
            name = normalized_member_name(member.name)
            assert not member.name.startswith('/'), 'Archive contains an absolute path'
            assert '..' not in [p for p in name.split('/') if p], 'Archive contains path traversal'
            assert not member.issym() and not member.islnk(), 'Archive contains a link'

            if member.isdir():
                assert name in ('', '.', 'safe_zone'), 'Archive contains an unnecessary nested directory'
                continue

            assert member.isfile(), 'Archive contains a non-regular entry'
            parts = [p for p in name.split('/') if p and p != '.']
            if len(parts) == 1:
                basename = parts[0]
                layout.add('direct')
            elif len(parts) == 2 and parts[0] == 'safe_zone':
                basename = parts[1]
                layout.add('safe_zone')
            else:
                pytest.fail('Clean archive is not completely flattened: ' + member.name)
            assert basename not in files, 'Archive contains duplicate flattened filenames'
            extracted = tar.extractfile(member)
            assert extracted is not None
            files[basename] = extracted.read()
    assert len(layout) <= 1, 'Archive mixes direct and safe_zone layouts'
    return files


def test_cleanup_script_exists_after_execution():
    assert os.path.isfile('/home/user/cleanup.sh')
    assert not os.path.islink('/home/user/cleanup.sh')


def test_zip_slip_mitigated():
    """Ensure the malicious path did not overwrite files outside the safe zone."""
    assert not os.path.exists('/home/user/data.csv'), (
        'Zip slip vulnerability was not mitigated; /home/user/data.csv was created.'
    )


def test_clean_logs_archive_exists():
    """Check that the final compressed archive exists."""
    archive_path = '/home/user/clean_logs.tar.bz2'
    assert os.path.isfile(archive_path), f'{archive_path} does not exist.'
    assert tarfile.is_tarfile(archive_path), f'{archive_path} is not a valid tarball.'


def test_archive_contents_and_redaction():
    """Retain the original conversion, splitting, flattening, and redaction assertions."""
    archive_path = '/home/user/clean_logs.tar.bz2'
    if not os.path.isfile(archive_path) or not tarfile.is_tarfile(archive_path):
        pytest.fail('Cannot test contents because archive is missing or invalid.')

    files = read_and_validate_archive()
    base_files = list(files)

    assert 'access.log' in base_files, 'access.log not found in archive. Flattening may have failed.'
    assert 'data.tsv' in base_files, 'data.tsv not found; CSV to TSV conversion failed.'
    assert 'data.csv' not in base_files, 'data.csv still exists in archive; it should have been removed.'
    assert 'server.log.partaa' in base_files, 'server.log.partaa not found; splitting failed.'
    assert 'server.log.partab' in base_files, 'server.log.partab not found; splitting failed.'
    assert 'server.log' not in base_files, 'server.log still exists; it should have been removed after splitting.'

    data_tsv_content = files['data.tsv'].decode()
    assert '1\talice\t***' in data_tsv_content, (
        'data.tsv does not contain the expected tab-separated and redacted content.'
    )
    assert ',' not in data_tsv_content, 'data.tsv still contains commas.'

    access_log_content = files['access.log'].decode()
    assert 'User login from ***' in access_log_content, 'access.log was not properly redacted.'
    assert '192.168.1.100' not in access_log_content, 'Unredacted IP found in access.log.'

    server_partaa_content = files['server.log.partaa'].decode()
    assert 'Line 1: ***' in server_partaa_content, 'server.log.partaa was not properly redacted.'
    assert '192.168.1.1' not in server_partaa_content, 'Unredacted IP found in server.log.partaa.'
    assert len(server_partaa_content.strip().split('\n')) == 5, 'server.log.partaa does not have exactly 5 lines.'


def test_safe_zone_is_flat_and_exact():
    expected = expected_files()
    assert os.path.isdir('/home/user/safe_zone')
    entries = list(os.scandir('/home/user/safe_zone'))
    assert all(entry.is_file(follow_symlinks=False) for entry in entries), (
        'safe_zone must contain only direct regular files and no subdirectories or links'
    )
    actual = {}
    for entry in entries:
        with open(entry.path, 'rb') as f:
            actual[entry.name] = f.read()
    assert actual == expected, 'safe_zone does not exactly match the required processed output'


def test_archive_is_flat_and_exact():
    assert read_and_validate_archive() == expected_files(), (
        'The final archive does not contain exactly all required cleaned files and contents'
    )
TEST_EOF

            if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
                reward=1
            fi
        fi
    fi
fi

echo "$reward" > /logs/verifier/reward.txt
