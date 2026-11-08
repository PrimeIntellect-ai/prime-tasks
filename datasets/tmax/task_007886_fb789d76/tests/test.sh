#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import signal
import struct
import subprocess
import tempfile
import uuid

MANIFEST_PATH = "/home/user/backup_manifest.txt"
WAL_DATA_DIR = "/home/user/wal_data"
HOME_DIR = "/home/user"


def compute_expected_manifest(wal_dir):
    valid_files = []

    if not os.path.isdir(wal_dir):
        return ""

    for filename in os.listdir(wal_dir):
        if not filename.endswith('.wal'):
            continue

        filepath = os.path.join(wal_dir, filename)
        if not os.path.isfile(filepath):
            continue

        file_size = os.path.getsize(filepath)
        if file_size < 16:
            continue

        with open(filepath, 'rb') as f:
            header = f.read(16)

        if len(header) < 16:
            continue

        magic = header[0:4]
        if magic != b'WAL!':
            continue

        seq = struct.unpack('<I', header[4:8])[0]
        payload_size = struct.unpack('<Q', header[8:16])[0]

        if file_size == 16 + payload_size:
            valid_files.append((seq, filename, payload_size))

    valid_files.sort(key=lambda x: x[0])

    lines = []
    for seq, filename, payload_size in valid_files:
        lines.append(f"{seq:08d} {filename} {payload_size}")

    return "\n".join(lines) + ("\n" if lines else "")


def test_manifest_exists():
    assert os.path.exists(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} was not created."
    assert os.path.isfile(MANIFEST_PATH), f"{MANIFEST_PATH} is not a regular file."


def test_manifest_contents():
    expected_content = compute_expected_manifest(WAL_DATA_DIR)

    with open(MANIFEST_PATH, 'r') as f:
        actual_content = f.read()

    # Normalize line endings and trailing whitespace for comparison
    expected_lines = [line.strip() for line in expected_content.strip().split('\n') if line.strip()]
    actual_lines = [line.strip() for line in actual_content.strip().split('\n') if line.strip()]

    assert actual_lines == expected_lines, (
        f"Manifest contents do not match expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def find_artifacts(work_dir):
    source_extensions = ('.cpp', '.cc', '.cxx', '.c++', '.C')
    sources = []
    executables = []

    for root, dirs, files in os.walk(HOME_DIR):
        dirs[:] = [d for d in dirs if d not in {'.cache', '.git'}]
        for name in files:
            path = os.path.join(root, name)
            if os.path.islink(path) or not os.path.isfile(path):
                continue
            if name.endswith(source_extensions):
                sources.append(path)
            try:
                if os.access(path, os.X_OK):
                    with open(path, 'rb') as f:
                        if f.read(4) == b'\x7fELF':
                            copied = os.path.join(work_dir, f"submitted_{len(executables)}")
                            shutil.copy2(path, copied)
                            os.chmod(copied, 0o755)
                            executables.append(copied)
            except OSError:
                pass

    return sorted(sources), executables


def compile_sources(sources, work_dir):
    candidates = []
    groups = [[source] for source in sources]
    if len(sources) > 1:
        groups.append(sources)

    for index, group in enumerate(groups):
        output = os.path.join(work_dir, f"compiled_{index}")
        result = subprocess.run(
            ['g++', '-std=c++17', '-O2', *group, '-o', output],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        if result.returncode == 0 and os.path.isfile(output):
            os.chmod(output, 0o755)
            candidates.append(output)

    return candidates


def make_wal(filename, seq, declared_size, actual_size, magic=b'WAL!'):
    with open(os.path.join(WAL_DATA_DIR, filename), 'wb') as f:
        f.write(magic)
        f.write(struct.pack('<I', seq))
        f.write(struct.pack('<Q', declared_size))
        f.write(os.urandom(actual_size))


def install_dynamic_fixtures(token):
    if os.path.lexists(WAL_DATA_DIR):
        if os.path.isdir(WAL_DATA_DIR) and not os.path.islink(WAL_DATA_DIR):
            shutil.rmtree(WAL_DATA_DIR)
        else:
            os.unlink(WAL_DATA_DIR)
    os.makedirs(WAL_DATA_DIR, mode=0o777)

    make_wal(f"later_{token}.wal", 700003, 37, 37)
    make_wal(f"first_{token}.wal", 19, 0, 0)
    make_wal(f"middle_{token}.wal", 42017, 113, 113)
    make_wal(f"short_{token}.wal", 88, 90, 17)
    make_wal(f"long_{token}.wal", 89, 12, 13)
    make_wal(f"badmagic_{token}.wal", 1, 9, 9, b'NOPE')
    with open(os.path.join(WAL_DATA_DIR, f"tiny_{token}.wal"), 'wb') as f:
        f.write(b'WAL!tiny')
    make_wal(f"ignored_{token}.bin", 2, 5, 5)


def run_program(path, expected, token):
    install_dynamic_fixtures(token)
    if os.path.lexists(MANIFEST_PATH):
        if os.path.isdir(MANIFEST_PATH) and not os.path.islink(MANIFEST_PATH):
            shutil.rmtree(MANIFEST_PATH)
        else:
            os.unlink(MANIFEST_PATH)

    process = subprocess.Popen(
        [path],
        cwd=HOME_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        return False, "timed out"

    if process.returncode != 0:
        return False, f"exit code {process.returncode}: {stderr[-500:]}"
    if not os.path.isfile(MANIFEST_PATH):
        return False, "did not create a regular manifest file"
    try:
        with open(MANIFEST_PATH, 'r', encoding='utf-8') as f:
            actual = f.read()
    except Exception as exc:
        return False, f"could not read manifest: {exc}"
    if actual != expected:
        return False, f"wrong dynamic manifest: {actual!r}"
    return True, "ok"


def test_cpp_source_and_compiled_program_on_dynamic_wals():
    work_dir = tempfile.mkdtemp(prefix='archiver_verifier_')
    backup_dir = os.path.join(work_dir, 'original_wal')
    manifest_existed = os.path.isfile(MANIFEST_PATH)
    original_manifest = None
    if manifest_existed:
        with open(MANIFEST_PATH, 'rb') as f:
            original_manifest = f.read()
    shutil.copytree(WAL_DATA_DIR, backup_dir)

    try:
        sources, submitted_executables = find_artifacts(work_dir)
        assert sources, "No C++ source file was found under /home/user."
        assert submitted_executables, "No compiled ELF executable was found under /home/user."

        compiled_candidates = compile_sources(sources, work_dir)
        assert compiled_candidates, "The submitted C++ source could not be compiled with g++."

        token = uuid.uuid4().hex[:12]
        install_dynamic_fixtures(token)
        expected = compute_expected_manifest(WAL_DATA_DIR)

        submitted_results = []
        submitted_ok = False
        for candidate in submitted_executables:
            ok, detail = run_program(candidate, expected, token)
            submitted_results.append(f"{candidate}: {detail}")
            if ok:
                submitted_ok = True
                break
        assert submitted_ok, (
            "No submitted compiled executable correctly processed the dynamic WAL files.\n" +
            "\n".join(submitted_results)
        )

        compiled_results = []
        compiled_ok = False
        for candidate in compiled_candidates:
            ok, detail = run_program(candidate, expected, token)
            compiled_results.append(f"{candidate}: {detail}")
            if ok:
                compiled_ok = True
                break
        assert compiled_ok, (
            "No program compiled from the submitted C++ source correctly processed the dynamic WAL files.\n" +
            "\n".join(compiled_results)
        )
    finally:
        if os.path.lexists(WAL_DATA_DIR):
            if os.path.isdir(WAL_DATA_DIR) and not os.path.islink(WAL_DATA_DIR):
                shutil.rmtree(WAL_DATA_DIR)
            else:
                os.unlink(WAL_DATA_DIR)
        shutil.copytree(backup_dir, WAL_DATA_DIR)

        if os.path.lexists(MANIFEST_PATH):
            if os.path.isdir(MANIFEST_PATH) and not os.path.islink(MANIFEST_PATH):
                shutil.rmtree(MANIFEST_PATH)
            else:
                os.unlink(MANIFEST_PATH)
        if manifest_existed:
            with open(MANIFEST_PATH, 'wb') as f:
                f.write(original_manifest)
        shutil.rmtree(work_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
