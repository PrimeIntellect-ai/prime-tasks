#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import subprocess
import tarfile
from pathlib import Path

HOME = Path('/home/user')
MANIFEST = HOME / 'manifest.txt'
ARCHIVE = HOME / 'config_backup.tar.gz'
BINARY = HOME / 'config_archiver'
SOURCE = HOME / 'config_archiver.c'


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def run(cmd, expected_success=True):
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=20)
    if expected_success:
        assert result.returncode == 0, (
            f"Command failed ({result.returncode}): {cmd}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    else:
        assert result.returncode != 0, f"Command unexpectedly succeeded: {cmd}"
    return result


def remove_outputs():
    for path in (MANIFEST, ARCHIVE):
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def verify_outputs(expected_files, expected_manifest_paths):
    assert MANIFEST.is_file(), f"Manifest file missing at {MANIFEST}"
    raw_lines = MANIFEST.read_text().splitlines()
    assert all(raw_lines), "Manifest contains blank lines"
    assert len(raw_lines) == len(expected_manifest_paths), (
        f"Expected exactly {len(expected_manifest_paths)} manifest lines, got {len(raw_lines)}"
    )

    expected_lines = [
        f"{sha256(expected_files[path])} {path}"
        for path in sorted(expected_manifest_paths)
    ]
    assert raw_lines == expected_lines, (
        "Manifest must contain correct SHA-256 values and be sorted by relative path"
    )
    for line in raw_lines:
        assert re.fullmatch(r'[0-9a-f]{64} [^\n]+', line), f"Invalid manifest line: {line!r}"
        parts = line.split()
        assert len(parts) == 2, f"Invalid manifest line format: {line!r}"

    assert ARCHIVE.is_file(), f"Tarball missing at {ARCHIVE}"
    assert tarfile.is_tarfile(ARCHIVE), f"File {ARCHIVE} is not a valid tar archive"
    archived_files = {}
    with tarfile.open(ARCHIVE, 'r:gz') as tar:
        for member in tar.getmembers():
            name = member.name
            while name.startswith('./'):
                name = name[2:]
            assert not name.startswith('/'), f"Archive contains absolute path: {member.name}"
            assert '..' not in Path(name).parts, f"Archive contains unsafe path: {member.name}"
            assert name != 'staging' and not name.startswith('staging/'), (
                "Archive must not contain a staging wrapper directory"
            )
            if member.isfile():
                extracted = tar.extractfile(member)
                assert extracted is not None
                archived_files[name] = extracted.read()

    assert archived_files == expected_files, (
        f"Archive file set or contents differ. Found: {sorted(archived_files)}"
    )


def exercise(program, staging, expected_files, conf_paths):
    run([str(program)], expected_success=False)
    run([str(program), str(staging), 'extra-argument'], expected_success=False)
    remove_outputs()
    run([str(program), str(staging)])
    verify_outputs(expected_files, conf_paths)


def test_complete_archiver():
    # Preserve the original source assertions and require a real compiled executable.
    assert SOURCE.is_file(), f"C source file missing at {SOURCE}"
    source_text = SOURCE.read_text()
    assert 'openssl' in source_text.lower() or 'crypto' in source_text.lower(), (
        "C source file does not appear to use OpenSSL/libcrypto"
    )
    assert BINARY.is_file(), f"Compiled binary missing at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable"
    assert BINARY.read_bytes()[:4] == b'\x7fELF', f"{BINARY} is not an ELF binary"

    # Compile the submitted C source independently, proving the source itself implements
    # the behavior rather than merely accompanying an unrelated binary.
    rebuilt = Path('/tmp/config_archiver_rebuilt')
    run(['gcc', '-std=gnu11', '-O2', str(SOURCE), '-o', str(rebuilt), '-lcrypto'])
    assert rebuilt.read_bytes()[:4] == b'\x7fELF'
    linkage = run(['ldd', str(rebuilt)]).stdout.lower()
    assert 'libcrypto' in linkage, "Rebuilt C program does not link against libcrypto"

    # Use unpredictable paths and contents so a fixed manifest/archive cannot pass.
    token = secrets.token_hex(8)
    dynamic_root = Path('/tmp') / f'archiver_input_{token}'
    dynamic_files = {
        f'etc_{token}/app/net.conf': f'[network]\nbind_addr={token}\nport=9000\n'.encode(),
        f'var_{token}/deep/other.conf': f'value={secrets.token_hex(12)}\n'.encode(),
        f'var_{token}/deep/readme.txt': f'non-conf-{secrets.token_hex(12)}\n'.encode(),
    }
    for relative, data in dynamic_files.items():
        path = dynamic_root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    dynamic_conf = {p for p in dynamic_files if p.endswith('.conf')}

    exercise(rebuilt, dynamic_root, dynamic_files, dynamic_conf)
    exercise(BINARY, dynamic_root, dynamic_files, dynamic_conf)

    # Verify staging has exactly the migrated copies requested by the original task.
    expected_actual = {
        'etc/app1/net.conf': b'[network]\nbind_addr=192.168.1.100\nport=8080\n',
        'etc/app2/settings.conf': b'debug=true\nbind_addr=10.0.0.5\ntimeout=30\n',
        'var/lib/app3/data.conf': b'path=/var/data\nbind_addr=127.0.0.1\n',
    }
    staging = HOME / 'staging'
    assert staging.is_dir(), f"Staging directory missing at {staging}"
    staged_files = {
        str(path.relative_to(staging)): path.read_bytes()
        for path in staging.rglob('*') if path.is_file()
    }
    assert staged_files == expected_actual, "Staged file set or migrated contents are incorrect"
    assert 'opt/ignored/skip.conf' not in staged_files
    assert all(b'server_ip=' not in data for path, data in staged_files.items() if path.endswith('.conf'))

    # Delete any prebuilt artifacts and require the submitted binary to regenerate both.
    exercise(BINARY, staging, expected_actual, set(expected_actual))

    # Preserve the original exact manifest hash assertions.
    lines = [line.strip() for line in MANIFEST.read_text().splitlines() if line.strip()]
    assert len(lines) == 3, f"Expected exactly 3 lines in manifest.txt, but got {len(lines)}"
    actual_manifest = {}
    for line in lines:
        parts = line.split()
        assert len(parts) == 2, f"Invalid manifest line format: '{line}'"
        checksum, path = parts
        actual_manifest[path] = checksum
    for path, content in expected_actual.items():
        assert path in actual_manifest, f"Expected path {path} not found in manifest"
        expected_hash = hashlib.sha256(content).hexdigest()
        assert actual_manifest[path] == expected_hash, f"Checksum mismatch for {path}"

    # Preserve the original named tar-member assertions.
    with tarfile.open(ARCHIVE, 'r:gz') as tar:
        names = [n[2:] if n.startswith('./') else n for n in tar.getnames()]
    for path in expected_actual:
        assert path in names, f"Expected file {path} not found in tarball. Found: {names}"

    # Preserve and strengthen the original-system integrity assertions.
    original_expected = {
        HOME / 'sys_root/etc/app1/net.conf': b'[network]\nserver_ip=192.168.1.100\nport=8080\n',
        HOME / 'sys_root/etc/app2/settings.conf': b'debug=true\nserver_ip=10.0.0.5\ntimeout=30\n',
        HOME / 'sys_root/var/lib/app3/data.conf': b'path=/var/data\nserver_ip=127.0.0.1\n',
        HOME / 'sys_root/opt/ignored/skip.conf': b'server_ip=0.0.0.0\n',
    }
    for path, expected in original_expected.items():
        assert path.is_file(), f"Original file {path} is missing"
        actual = path.read_bytes()
        assert expected.splitlines()[1 if b'app1' in str(path).encode() else 0] in actual
        assert actual == expected, f"Original file {path} was modified"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
