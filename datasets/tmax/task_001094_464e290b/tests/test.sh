#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path

import pytest

PIGZ = Path('/home/user/bin/pigz')
SCRIPT = Path('/home/user/archive.sh')
CONFIG = Path('/home/user/archive_config.conf')
ARCHIVE = Path('/home/user/archived_logs.tar.gz')
SOURCE = Path('/var/log/app_logs')


def run(cmd, timeout=180, **kwargs):
    return subprocess.run(cmd, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, timeout=timeout, **kwargs)


def parse_config(path):
    values = {}
    for raw in Path(path).read_text().splitlines():
        raw = raw.strip()
        if raw and not raw.startswith('#') and '=' in raw:
            key, value = raw.split('=', 1)
            values[key.strip()] = value.strip()
    return values


def regular_log_members(tar):
    result = {}
    for member in tar.getmembers():
        if member.isfile() and member.name.endswith('.log'):
            name = os.path.basename(member.name.rstrip('/'))
            assert name not in result, f'Duplicate archived log basename: {name}'
            extracted = tar.extractfile(member)
            assert extracted is not None
            result[name] = extracted.read()
    return result


def test_pigz_compiled_and_copied():
    pigz_path = '/home/user/bin/pigz'
    assert os.path.isfile(pigz_path), f'pigz executable is missing at {pigz_path}.'
    assert os.access(pigz_path, os.X_OK), f'pigz at {pigz_path} is not executable.'

    installed = PIGZ.read_bytes()
    assert installed.startswith(b'\x7fELF'), 'Installed pigz must be a compiled ELF binary.'

    version = run([str(PIGZ), '--version']).stdout.decode('utf-8', 'replace')
    assert re.search(r'\bpigz\s+2\.8\b', version), f'Unexpected pigz version output: {version!r}'

    payload = os.urandom(65536) + (b'pigz-functional-test\n' * 1000)
    compressed = run([str(PIGZ), '-9', '-c'], input=payload).stdout
    assert gzip.decompress(compressed) == payload, 'Installed pigz failed a compression round trip.'

    source_dir = Path('/app/pigz-2.8')
    assert source_dir.is_dir(), 'Vendored pigz source directory is missing.'
    run(['make', 'clean'], cwd=str(source_dir))
    run(['make'], cwd=str(source_dir))
    rebuilt = source_dir / 'pigz'
    assert rebuilt.is_file() and os.access(rebuilt, os.X_OK), 'Vendored pigz source did not compile.'
    assert installed == rebuilt.read_bytes(), (
        'Installed /home/user/bin/pigz is not the binary produced from the vendored source.'
    )


def test_archive_script_exists():
    script_path = '/home/user/archive.sh'
    assert os.path.isfile(script_path), f'Archive script is missing at {script_path}.'
    assert os.access(script_path, os.X_OK) or os.access(script_path, os.R_OK), f'Archive script at {script_path} must be readable or executable.'


def test_script_uses_config_filters_all_logs_and_invokes_installed_pigz():
    original_config = CONFIG.read_bytes()
    real_pigz = PIGZ.with_name('pigz.verifier-real')
    assert not real_pigz.exists(), f'Unexpected file blocks verifier instrumentation: {real_pigz}'

    with tempfile.TemporaryDirectory(prefix='archive-verifier-') as td:
        root = Path(td)
        source = root / 'input'
        target = root / 'result.tar.gz'
        calls = root / 'pigz.calls'
        source.mkdir()

        token = os.urandom(8).hex()
        marker1 = f'DROP_A_{token}'
        marker2 = f'DROP_B_{token}'
        inputs = {
            'alpha.log': (
                f'first retained {token}\n'
                f'[{marker1}] remove this line\n'
                f'second retained {token}\n'
            ).encode(),
            'beta.log': (
                f'[{marker2}] remove this too\n'
                f'[INFO] retained information {token}\n'
            ).encode(),
            'gamma.log': (
                f'[{marker1}] only excluded one\n'
                f'[{marker2}] only excluded two\n'
            ).encode(),
        }
        expected = {
            'alpha.log': f'first retained {token}\nsecond retained {token}\n'.encode(),
            'beta.log': f'[INFO] retained information {token}\n'.encode(),
            'gamma.log': b'',
        }
        for name, data in inputs.items():
            (source / name).write_bytes(data)
        (source / 'must_not_be_archived.txt').write_text('not a log\n')

        CONFIG.write_text(
            f'SOURCE_DIR={source}\n'
            f'EXCLUDE_PATTERN_1=\\[{marker1}\\]\n'
            f'EXCLUDE_PATTERN_2=\\[{marker2}\\]\n'
            'COMPRESSION_LEVEL=-7\n'
            f'TARGET_FILE={target}\n'
        )

        os.replace(PIGZ, real_pigz)
        PIGZ.write_text(
            '#!/bin/bash\n'
            f'printf "%s\\0" "$@" >> {calls!s}\n'
            f'exec {real_pigz!s} "$@"\n'
        )
        PIGZ.chmod(0o755)

        try:
            run(['/bin/bash', str(SCRIPT)])
            assert target.is_file(), 'The script did not write TARGET_FILE from the test config.'
            assert calls.is_file(), 'The script did not invoke /home/user/bin/pigz.'
            arguments = calls.read_bytes().split(b'\0')
            assert b'-7' in arguments, 'The script did not pass configured COMPRESSION_LEVEL to pigz.'

            with tarfile.open(target, 'r:gz') as tar:
                actual = regular_log_members(tar)
                regular_names = [os.path.basename(m.name.rstrip('/')) for m in tar.getmembers() if m.isfile()]
            assert set(regular_names) == set(expected), 'Archive must contain only the configured source .log files.'
            assert actual == expected, 'Archived logs do not exactly match the configured filtering result.'
        finally:
            CONFIG.write_bytes(original_config)
            if PIGZ.exists():
                PIGZ.unlink()
            if real_pigz.exists():
                os.replace(real_pigz, PIGZ)


def test_run_script_and_verify_expected_application_logs():
    config = parse_config(CONFIG)
    assert config.get('SOURCE_DIR') == str(SOURCE)
    assert config.get('TARGET_FILE') == str(ARCHIVE)

    run(['/bin/bash', str(SCRIPT)])
    assert ARCHIVE.is_file(), 'Running archive.sh did not generate the configured target archive.'

    pattern1 = re.compile(config['EXCLUDE_PATTERN_1'])
    pattern2 = re.compile(config['EXCLUDE_PATTERN_2'])
    source_files = sorted(SOURCE.glob('*.log'))
    assert len(source_files) == 5, 'The expected five source logs are not present.'

    expected = {}
    for path in source_files:
        kept = []
        for line in path.read_text().splitlines(keepends=True):
            if not pattern1.search(line) and not pattern2.search(line):
                kept.append(line)
        expected[path.name] = ''.join(kept).encode()

    with tarfile.open(ARCHIVE, 'r:gz') as tar:
        actual = regular_log_members(tar)
        all_regular = [os.path.basename(m.name.rstrip('/')) for m in tar.getmembers() if m.isfile()]

    assert set(all_regular) == set(expected), 'Archive must contain exactly the five expected .log files.'
    assert actual == expected, 'Archived application logs do not exactly match the filtered source logs.'
    for name, content in actual.items():
        assert b'[INFO]' in content, f'Expected retained [INFO] content is missing from {name}.'


def test_archive_file_exists_and_size_metric():
    archive_path = '/home/user/archived_logs.tar.gz'
    assert os.path.isfile(archive_path), f'Target archive file is missing at {archive_path}.'

    file_size = os.path.getsize(archive_path)
    threshold = 150000

    assert file_size <= threshold, (
        f'Archive size metric failed: measured {file_size} bytes, '
        f'which is not <= threshold of {threshold} bytes. '
        'Ensure [DEBUG] and [TRACE] lines are stripped and -9 compression is used.'
    )


def test_archive_contents_filtered():
    archive_path = '/home/user/archived_logs.tar.gz'
    assert os.path.isfile(archive_path), 'Target archive file is missing.'

    try:
        with tarfile.open(archive_path, 'r:gz') as tar:
            members = tar.getmembers()
            assert len(members) > 0, 'The archive is empty.'

            for member in members:
                if member.isfile() and member.name.endswith('.log'):
                    f = tar.extractfile(member)
                    if f is not None:
                        content = f.read().decode('utf-8', errors='replace')
                        assert '[DEBUG]' not in content, f'Found [DEBUG] lines in archived file {member.name}.'
                        assert '[TRACE]' not in content, f'Found [TRACE] lines in archived file {member.name}.'
    except tarfile.ReadError:
        pytest.fail(f'Could not read {archive_path} as a valid gzip-compressed tar archive.')
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
