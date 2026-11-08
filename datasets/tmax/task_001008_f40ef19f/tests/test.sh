#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tarfile
import tempfile


def test_pigz_compiled():
    """Verify that pigz is a real compiled executable."""
    pigz_path = '/app/pigz-2.8/pigz'
    assert os.path.isfile(pigz_path), f"Compiled pigz binary not found at {pigz_path}."
    assert os.access(pigz_path, os.X_OK), f"pigz binary at {pigz_path} is not executable."

    with open(pigz_path, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f"{pigz_path} is not a compiled ELF binary."

    result = subprocess.run([pigz_path, '-V'], capture_output=True, text=True, timeout=10)
    version_output = result.stdout + result.stderr
    assert result.returncode == 0, f"pigz -V failed: {version_output}"
    assert re.search(r'pigz\s+2\.8', version_output, re.IGNORECASE), (
        f"Unexpected pigz version output: {version_output!r}"
    )


def test_script_exists_and_executable():
    """Verify that the process_logs.sh script exists and is executable."""
    script_path = '/home/user/process_logs.sh'
    assert os.path.isfile(script_path), f"Script not found at {script_path}."
    assert os.access(script_path, os.X_OK), f"Script at {script_path} is not executable."


def test_archive_exists():
    """Verify that the final archive was generated."""
    archive_path = '/home/user/final_archive.tar.gz'
    assert os.path.isfile(archive_path), f"Final archive not found at {archive_path}."


def test_archive_contents():
    """Verify that the archive contains exactly the valid WAL files and their source bytes."""
    archive_path = '/home/user/final_archive.tar.gz'
    assert tarfile.is_tarfile(archive_path), f"{archive_path} is not a valid tar archive."

    with tarfile.open(archive_path, 'r:*') as tar:
        members = tar.getmembers()
        names = [m.name for m in members]

        # Preserve the original basename-based assertions.
        basenames = [os.path.basename(m) for m in names if os.path.basename(m).startswith('wal_')]
        expected_valid = [f"wal_{i:03d}.log" for i in range(1, 21)]
        expected_invalid = [f"wal_{i:03d}.log" for i in range(21, 36)]

        for valid_file in expected_valid:
            assert valid_file in basenames, f"Valid WAL file {valid_file} is missing from the archive."

        for invalid_file in expected_invalid:
            assert invalid_file not in basenames, f"Invalid WAL file {invalid_file} was incorrectly included in the archive."

        assert len(basenames) == len(expected_valid), (
            f"Archive contains an unexpected number of WAL files. "
            f"Expected {len(expected_valid)}, got {len(basenames)}."
        )

        # Ensure each archived WAL is a regular file whose bytes exactly match its source.
        for basename in expected_valid:
            matches = [m for m in members if os.path.basename(m.name) == basename]
            assert len(matches) == 1, f"Expected exactly one archive member for {basename}."
            member = matches[0]
            assert member.isfile(), f"Archive member {member.name} is not a regular file."
            extracted = tar.extractfile(member)
            assert extracted is not None
            archived_bytes = extracted.read()
            source_path = os.path.join('/home/user/wal_logs', basename)
            with open(source_path, 'rb') as source:
                source_bytes = source.read()
            assert source_bytes[:4] == b'WAL_', f"Source {basename} lacks WAL magic bytes."
            assert archived_bytes == source_bytes, f"Archived contents of {basename} differ from the source."


def test_archive_size_metric():
    """Verify that the final archive size meets the original metric threshold."""
    archive_path = '/home/user/final_archive.tar.gz'
    assert os.path.isfile(archive_path), f"Final archive not found at {archive_path}."

    file_size = os.path.getsize(archive_path)
    threshold = 500000
    assert file_size <= threshold, (
        f"Archive size metric failed: {file_size} bytes is not <= {threshold} bytes. "
        "Ensure you are filtering invalid files and using maximum compression (-9)."
    )


def test_script_processes_fresh_inputs_with_pigz():
    """Execute the submitted script against verifier-created files and validate exact bytes."""
    script_path = '/home/user/process_logs.sh'
    config_path = '/home/user/archiver.conf'
    archive_path = '/home/user/final_archive.tar.gz'
    pigz_path = '/app/pigz-2.8/pigz'

    token = secrets.token_hex(8)
    test_dir = tempfile.mkdtemp(prefix=f'wal_verify_{token}_', dir='/home/user')
    real_pigz = f'/app/pigz-2.8/.pigz-verifier-{token}'
    invocation_log = f'/tmp/pigz-invocation-{token}'

    valid_data = {
        f'wal_{token}_alpha.log': b'WAL_' + (b'ALPHA_RECORD_' + token.encode()) * 8192,
        f'wal_{token}_beta.log': b'WAL_' + bytes(range(256)) * 512,
        f'wal_{token}_gamma.log': b'WAL_' + b'G' * 131071,
    }
    invalid_data = {
        f'wal_{token}_bad.log': b'BAD_' + b'WAL_' * 4096,
        f'wal_{token}_empty.log': b'',
    }

    with open(config_path, 'rb') as f:
        original_config = f.read()

    try:
        for name, data in {**valid_data, **invalid_data}.items():
            with open(os.path.join(test_dir, name), 'wb') as f:
                f.write(data)

        with open(config_path, 'w') as f:
            f.write('# Verifier-generated archiver configuration\n')
            f.write(f'LOG_DIR={test_dir}\n')
            f.write('MAX_THREADS=4\n')

        # Interpose a wrapper to prove the script invokes the compiled pigz with -9.
        os.rename(pigz_path, real_pigz)
        with open(pigz_path, 'w') as f:
            f.write('#!/bin/bash\n')
            f.write(f"printf '%s\\0' \"$@\" >> {invocation_log!r}\n")
            f.write(f'exec {real_pigz!r} "$@"\n')
        os.chmod(pigz_path, 0o755)

        if os.path.exists(archive_path):
            os.unlink(archive_path)

        result = subprocess.run([script_path], capture_output=True, text=True, timeout=120)
        assert result.returncode == 0, (
            f"process_logs.sh failed on fresh inputs. stdout={result.stdout!r}, "
            f"stderr={result.stderr!r}"
        )
        assert os.path.isfile(archive_path), "Script did not generate final_archive.tar.gz."

        with open(archive_path, 'rb') as f:
            assert f.read(2) == b'\x1f\x8b', "Final archive is not gzip-compressed."

        assert os.path.isfile(invocation_log), "The script did not invoke /app/pigz-2.8/pigz."
        with open(invocation_log, 'rb') as f:
            args = [a.decode(errors='replace') for a in f.read().split(b'\0') if a]
        assert any(arg == '-9' or arg.startswith('-9') for arg in args), (
            f"pigz was not invoked at maximum compression level -9; arguments were {args!r}."
        )

        with tarfile.open(archive_path, 'r:gz') as tar:
            file_members = [m for m in tar.getmembers() if m.isfile()]
            archived_names = [os.path.basename(m.name) for m in file_members]
            assert len(archived_names) == len(valid_data), (
                f"Expected exactly {len(valid_data)} archived files, got {archived_names!r}."
            )
            assert set(archived_names) == set(valid_data), (
                f"Archive file set is wrong: expected {sorted(valid_data)}, got {sorted(archived_names)}."
            )

            for name, expected_bytes in valid_data.items():
                matches = [m for m in file_members if os.path.basename(m.name) == name]
                assert len(matches) == 1, f"Expected exactly one member for {name}."
                extracted = tar.extractfile(matches[0])
                assert extracted is not None
                assert extracted.read() == expected_bytes, f"Archived bytes for {name} are incorrect."

            for name in invalid_data:
                assert name not in archived_names, f"Invalid WAL file {name} was archived."
    finally:
        with open(config_path, 'wb') as f:
            f.write(original_config)
        if os.path.exists(pigz_path):
            os.unlink(pigz_path)
        if os.path.exists(real_pigz):
            os.rename(real_pigz, pigz_path)
        if os.path.exists(invocation_log):
            os.unlink(invocation_log)
        shutil.rmtree(test_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
