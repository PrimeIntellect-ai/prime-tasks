#!/bin/bash
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

validate_submission() {
python3 - <<'PY'
import os
import stat

source = '/home/user/archiver.cpp'
binary = '/home/user/archiver'

for path in (source, binary):
    st = os.lstat(path)
    assert stat.S_ISREG(st.st_mode), f'{path} must be a regular file'

assert os.access(binary, os.X_OK), f'{binary} is not executable'
with open(binary, 'rb') as f:
    assert f.read(4) == b'\x7fELF', f'{binary} is not a compiled ELF executable'
PY

  timeout 30s g++ -std=c++17 -O2 /home/user/archiver.cpp -o /tmp/verifier_archiver || return 1

  rm -rf /home/user/project_data
  rm -f /home/user/manifest_v1.csv /home/user/manifest_v2.csv /home/user/incremental.bin

  python3 - <<'PY'
import base64
import hashlib
import json
import os
import secrets

project = '/home/user/project_data'
os.makedirs(project, mode=0o755)

suffix = secrets.token_hex(6)
files = {
    f'stable_{suffix}.txt': secrets.token_bytes(41),
    f'src_{suffix}/changed.bin': secrets.token_bytes(137),
    f'assets_{suffix}/new.dat': secrets.token_bytes(83),
}

for rel, data in files.items():
    full = os.path.join(project, rel)
    os.makedirs(os.path.dirname(full), mode=0o755, exist_ok=True)
    with open(full, 'wb') as f:
        f.write(data)

stable = f'stable_{suffix}.txt'
changed = f'src_{suffix}/changed.bin'
deleted = f'old_{suffix}/deleted.txt'
v1_lines = [
    f'{stable},{hashlib.sha256(files[stable]).hexdigest()}',
    f'{changed},{hashlib.sha256(secrets.token_bytes(29)).hexdigest()}',
    f'{deleted},{hashlib.sha256(b"deleted historical file").hexdigest()}',
]
v1_text = '\n'.join(v1_lines) + '\n'
with open('/home/user/manifest_v1.csv', 'w', encoding='utf-8', newline='') as f:
    f.write(v1_text)

snapshot = {
    'files': {rel: base64.b64encode(data).decode('ascii') for rel, data in files.items()},
    'manifest_v1': v1_text,
}
with open('/root/verifier_expected.json', 'w', encoding='utf-8') as f:
    json.dump(snapshot, f)
os.chmod('/root/verifier_expected.json', 0o600)

for root, dirs, names in os.walk(project):
    os.chmod(root, 0o755)
    for name in names:
        os.chmod(os.path.join(root, name), 0o644)
os.chmod('/home/user/manifest_v1.csv', 0o644)
PY

  (cd /home/user && timeout 20s runuser -u user -- /tmp/verifier_archiver) || return 1

  cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import struct

PROJECT_DIR = '/home/user/project_data'
MANIFEST_V1 = '/home/user/manifest_v1.csv'
MANIFEST_V2 = '/home/user/manifest_v2.csv'
INCREMENTAL_BIN = '/home/user/incremental.bin'

with open('/root/verifier_expected.json', 'r', encoding='utf-8') as f:
    SNAPSHOT = json.load(f)
EXPECTED_FILES = {
    path: base64.b64decode(data) for path, data in SNAPSHOT['files'].items()
}

def compute_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b''):
            sha256.update(chunk)
    return sha256.hexdigest()

def get_current_files_and_hashes():
    files_hashes = {}
    for root, _, files in os.walk(PROJECT_DIR):
        for file in files:
            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, PROJECT_DIR)
            files_hashes[rel_path] = compute_sha256(full_path)
    return files_hashes

def get_v1_manifest():
    v1_hashes = {}
    if os.path.exists(MANIFEST_V1):
        with open(MANIFEST_V1, 'r') as f:
            for line in f:
                line = line.strip()
                if line:
                    parts = line.split(',', 1)
                    if len(parts) == 2:
                        v1_hashes[parts[0]] = parts[1]
    return v1_hashes

def test_source_inputs_were_not_modified():
    actual_paths = set()
    for root, _, files in os.walk(PROJECT_DIR):
        for name in files:
            full = os.path.join(root, name)
            rel = os.path.relpath(full, PROJECT_DIR)
            actual_paths.add(rel)
            assert rel in EXPECTED_FILES, f'Unexpected input file created: {rel}'
            with open(full, 'rb') as f:
                assert f.read() == EXPECTED_FILES[rel], f'Input file was modified: {rel}'
    assert actual_paths == set(EXPECTED_FILES), 'Project input files were deleted or renamed'

    with open(MANIFEST_V1, 'r', encoding='utf-8', newline='') as f:
        assert f.read() == SNAPSHOT['manifest_v1'], 'manifest_v1.csv was modified'

def test_manifest_v2_exists_and_correct():
    """Test that manifest_v2.csv exists and contains exactly the current files and their sha256 hashes."""
    assert os.path.isfile(MANIFEST_V2), f"{MANIFEST_V2} is missing"

    current_files = get_current_files_and_hashes()

    v2_hashes = {}
    with open(MANIFEST_V2, 'r') as f:
        lines = f.read().splitlines()

    for line in lines:
        if not line.strip():
            continue
        parts = line.split(',', 1)
        assert len(parts) == 2, f"Invalid line format in {MANIFEST_V2}: {line}"
        assert parts[0] not in v2_hashes, f"Duplicate path in {MANIFEST_V2}: {parts[0]}"
        v2_hashes[parts[0]] = parts[1]

    assert set(v2_hashes.keys()) == set(current_files.keys()), "Files in manifest_v2.csv do not match current files in project_data"

    for rel_path, expected_hash in current_files.items():
        assert v2_hashes[rel_path] == expected_hash, f"Hash for {rel_path} in {MANIFEST_V2} is incorrect"

    non_empty_lines = [line for line in lines if line.strip()]
    sorted_lines = sorted(non_empty_lines)
    assert non_empty_lines == sorted_lines, f"Lines in {MANIFEST_V2} are not sorted alphabetically"

def test_incremental_bin_exists_and_correct():
    """Test that incremental.bin exists and contains the correct changed files with proper binary format."""
    assert os.path.isfile(INCREMENTAL_BIN), f"{INCREMENTAL_BIN} is missing"

    current_files = get_current_files_and_hashes()
    v1_hashes = get_v1_manifest()

    expected_changed_files = []
    for rel_path, current_hash in current_files.items():
        if rel_path not in v1_hashes or v1_hashes[rel_path] != current_hash:
            expected_changed_files.append(rel_path)

    expected_changed_files.sort()

    with open(INCREMENTAL_BIN, 'rb') as f:
        magic = f.read(4)
        assert magic == b'ARCH', f"Invalid magic header in {INCREMENTAL_BIN}, expected 'ARCH', got {magic}"

        parsed_files = []
        while True:
            path_len_bytes = f.read(4)
            if not path_len_bytes:
                break
            assert len(path_len_bytes) == 4, "Unexpected EOF while reading path_length"
            path_len = struct.unpack('<I', path_len_bytes)[0]

            path_bytes = f.read(path_len)
            assert len(path_bytes) == path_len, "Unexpected EOF while reading path"
            path = path_bytes.decode('utf-8')

            file_size_bytes = f.read(8)
            assert len(file_size_bytes) == 8, "Unexpected EOF while reading file_size"
            file_size = struct.unpack('<Q', file_size_bytes)[0]

            file_data = f.read(file_size)
            assert len(file_data) == file_size, "Unexpected EOF while reading file_data"

            parsed_files.append((path, file_data))

    parsed_paths = [p[0] for p in parsed_files]
    assert parsed_paths == expected_changed_files, f"Expected changed files {expected_changed_files}, but got {parsed_paths} in {INCREMENTAL_BIN}"

    for path, file_data in parsed_files:
        full_path = os.path.join(PROJECT_DIR, path)
        with open(full_path, 'rb') as orig_f:
            expected_data = orig_f.read()
        assert file_data == expected_data, f"File data for {path} in {INCREMENTAL_BIN} does not match actual file content"
TEST_EOF

  python3 -m pytest /tmp/test_final_state.py -x --tb=short
}

if validate_submission 2>&1; then
  echo "1" > /logs/verifier/reward.txt
else
  echo "0" > /logs/verifier/reward.txt
fi
