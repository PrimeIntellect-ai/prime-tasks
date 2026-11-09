#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import os
import shlex
import shutil
import signal
import subprocess
import tarfile
import tempfile
import time
import uuid

WAL_CHECK_BIN = "/home/user/wal_check/target/release/wal_check"
PENDING_DIR = "/home/user/run/spool/pending"
PROCESSED_DIR = "/home/user/run/spool/processed"


def stop_process(proc):
    if proc is None or proc.poll() is not None:
        return
    try:
        os.killpg(proc.pid, signal.SIGTERM)
        proc.wait(timeout=3)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=3)


def stop_existing_services():
    subprocess.run(["pkill", "-f", "/home/user/services/producer.py"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["pkill", "-f", "/home/user/services/archiver.sh"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)


def clear_directory(path):
    os.makedirs(path, exist_ok=True)
    for name in os.listdir(path):
        target = os.path.join(path, name)
        if os.path.isdir(target) and not os.path.islink(target):
            shutil.rmtree(target)
        else:
            os.remove(target)


def read_archive(archive):
    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(archive, "r:gz") as tar:
            tar.extractall(path=tmpdir)

        extracted_files = os.listdir(tmpdir)
        assert "manifest.sha256" in extracted_files, "manifest.sha256 is missing from the archive root"

        wal_files = [f for f in extracted_files if f.endswith(".wal")]
        assert len(wal_files) > 0, "No .wal files found in the archive"

        manifest_path = os.path.join(tmpdir, "manifest.sha256")
        with open(manifest_path, "r") as f:
            manifest_lines = f.read().strip().splitlines()

        manifest_dict = {}
        for line in manifest_lines:
            parts = line.split()
            if len(parts) >= 2:
                manifest_dict[os.path.basename(parts[1])] = parts[0]

        contents = {}
        for wal_file in wal_files:
            wal_path = os.path.join(tmpdir, wal_file)
            with open(wal_path, "rb") as f:
                content_bytes = f.read()
            contents[wal_file] = content_bytes

            actual_sha256 = hashlib.sha256(content_bytes).hexdigest()
            assert wal_file in manifest_dict, f"{wal_file} not found in manifest.sha256"
            assert manifest_dict[wal_file] == actual_sha256, f"Checksum mismatch for {wal_file}"

            content_str = content_bytes.decode("utf-8", errors="ignore")
            lines = content_str.splitlines()
            assert lines, f"{wal_file} is empty"
            assert lines[0] == "WAL_START", f"{wal_file} missing WAL_START at the beginning"
            assert lines[-1] == "WAL_END", f"{wal_file} missing WAL_END at the end"
            assert "../" not in content_str, f"{wal_file} contains path traversal attempt '../'"
            assert "EXEC=" not in content_str, f"{wal_file} contains malicious execution attempt 'EXEC='"

        return contents, manifest_dict


def test_wal_check_corpus():
    assert os.path.isfile(WAL_CHECK_BIN), f"Executable not found at {WAL_CHECK_BIN}"
    assert os.access(WAL_CHECK_BIN, os.X_OK), f"File at {WAL_CHECK_BIN} is not executable"

    clean_dir = "/opt/corpus/clean"
    evil_dir = "/opt/corpus/evil"
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
                   if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
                  if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failures = []
    for cf in clean_files:
        if subprocess.run([WAL_CHECK_BIN, cf], capture_output=True).returncode != 0:
            clean_failures.append(os.path.basename(cf))

    evil_failures = []
    for ef in evil_files:
        if subprocess.run([WAL_CHECK_BIN, ef], capture_output=True).returncode == 0:
            evil_failures.append(os.path.basename(ef))

    error_msg = []
    if evil_failures:
        error_msg.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_msg.append(f"{len(clean_failures)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failures)}")
    assert not error_msg, " ; ".join(error_msg)


def test_wal_check_generated_cases_and_arity():
    token = uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix="wal-rules-") as tmpdir:
        cases = [
            (f"{token}_clean_a.wal", f"WAL_START\nDATA={token}\nWAL_END\n", True),
            (f"{token}_clean_b.wal", "WAL_START\nWAL_END\n", True),
            (f"{token}_bad_start.wal", f"NOT_WAL_START\nDATA={token}\nWAL_END\n", False),
            (f"{token}_missing_start.wal", f"DATA={token}\nWAL_END\n", False),
            (f"{token}_bad_end.wal", f"WAL_START\nDATA={token}\nNOT_WAL_END\n", False),
            (f"{token}_missing_end.wal", f"WAL_START\nDATA={token}", False),
            (f"{token}_traversal.wal", f"WAL_START\nPATH={token}/../secret\nWAL_END\n", False),
            (f"{token}_exec.wal", f"WAL_START\nPREFIX_{token}_EXEC=run\nWAL_END\n", False),
        ]
        paths = []
        for name, content, expected_clean in cases:
            path = os.path.join(tmpdir, name)
            with open(path, "w") as f:
                f.write(content)
            paths.append(path)
            result = subprocess.run([WAL_CHECK_BIN, path], capture_output=True)
            if expected_clean:
                assert result.returncode == 0, f"Generated clean WAL was rejected: {name}"
            else:
                assert result.returncode != 0, f"Generated evil WAL was accepted: {name}"

        assert subprocess.run([WAL_CHECK_BIN], capture_output=True).returncode != 0, "wal_check accepted zero arguments"
        assert subprocess.run([WAL_CHECK_BIN, paths[0], paths[1]], capture_output=True).returncode != 0, "wal_check accepted two arguments"


def test_archiver_uses_sanitizer_and_archives_actual_dynamic_input():
    stop_existing_services()
    clear_directory(PENDING_DIR)
    clear_directory(PROCESSED_DIR)

    token = uuid.uuid4().hex
    clean_name = f"generated_{token}_clean.wal"
    evil_name = f"generated_{token}_evil.wal"
    clean_bytes = f"WAL_START\nDATA={token}\nWAL_END\n".encode()
    evil_bytes = f"WAL_START\nDATA={token}\nEXEC=BAD_{token}\nWAL_END\n".encode()
    clean_path = os.path.join(PENDING_DIR, clean_name)
    evil_path = os.path.join(PENDING_DIR, evil_name)
    with open(clean_path, "wb") as f:
        f.write(clean_bytes)
    with open(evil_path, "wb") as f:
        f.write(evil_bytes)

    real_bin = WAL_CHECK_BIN + ".verifier-real-" + token
    call_log = os.path.join("/tmp", "wal-check-calls-" + token)
    os.replace(WAL_CHECK_BIN, real_bin)
    with open(WAL_CHECK_BIN, "w") as f:
        f.write("#!/bin/bash\n")
        f.write("printf '%s\\t%s\\n' \"$PWD\" \"$1\" >> " + shlex.quote(call_log) + "\n")
        f.write("exec " + shlex.quote(real_bin) + " \"$@\"\n")
    os.chmod(WAL_CHECK_BIN, 0o755)

    archiver = None
    try:
        archiver = subprocess.Popen(["bash", "/home/user/services/archiver.sh"], start_new_session=True)
        deadline = time.time() + 9
        while time.time() < deadline:
            if (not os.path.exists(clean_path) and not os.path.exists(evil_path)
                    and glob.glob(os.path.join(PROCESSED_DIR, "*.tar.gz"))):
                break
            time.sleep(0.2)
    finally:
        stop_process(archiver)
        if os.path.exists(WAL_CHECK_BIN):
            os.remove(WAL_CHECK_BIN)
        os.replace(real_bin, WAL_CHECK_BIN)

    assert not os.path.exists(evil_path), "Evil pending WAL was not deleted"
    assert not os.path.exists(clean_path), "Clean pending WAL was not consumed by the archiver"
    assert os.path.isfile(call_log), "archiver.sh never invoked the wal_check executable"

    checked_paths = set()
    with open(call_log, "r") as f:
        for line in f:
            cwd, sep, argument = line.rstrip("\n").partition("\t")
            if sep and argument:
                checked_paths.add(os.path.abspath(argument if os.path.isabs(argument) else os.path.join(cwd, argument)))
    assert clean_path in checked_paths, "archiver.sh did not inspect the generated clean WAL with wal_check"
    assert evil_path in checked_paths, "archiver.sh did not inspect the generated evil WAL with wal_check"

    archives = glob.glob(os.path.join(PROCESSED_DIR, "*.tar.gz"))
    assert archives, "No archive was produced for the generated input"
    found_clean = False
    for archive in archives:
        contents, manifest = read_archive(archive)
        assert evil_name not in contents, "Evil generated WAL was included in an archive"
        if clean_name in contents:
            found_clean = True
            assert contents[clean_name] == clean_bytes, "Archive did not contain the actual generated clean WAL"
            assert manifest[clean_name] == hashlib.sha256(clean_bytes).hexdigest()
    assert found_clean, "The actual generated clean WAL was not archived"


def test_pipeline_end_to_end():
    stop_existing_services()
    clear_directory(PENDING_DIR)
    clear_directory(PROCESSED_DIR)

    producer = subprocess.Popen(["python3", "/home/user/services/producer.py"], start_new_session=True)
    archiver = subprocess.Popen(["bash", "/home/user/services/archiver.sh"], start_new_session=True)
    try:
        time.sleep(12)
    finally:
        stop_process(producer)
        stop_process(archiver)

    archives = glob.glob(os.path.join(PROCESSED_DIR, "*.tar.gz"))
    assert archives, "No archives were produced in /home/user/run/spool/processed/"
    latest_archive = max(archives, key=os.path.getmtime)
    read_archive(latest_archive)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
