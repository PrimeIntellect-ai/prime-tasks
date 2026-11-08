#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import io
import json
import os
import secrets
import subprocess
import tarfile
import zipfile


def test_clean_docs_zip_exists_and_valid():
    zip_path = "/home/user/clean_docs.zip"
    assert os.path.exists(zip_path), f"Expected {zip_path} to exist."
    assert zipfile.is_zipfile(zip_path), f"Expected {zip_path} to be a valid zip file."


def test_clean_docs_zip_contents():
    zip_path = "/home/user/clean_docs.zip"
    expected_files = {
        "set1.zip_doc1.txt": b"Welcome to OmniCorp. This is doc1.",
        "set1.zip_doc2.txt": b"OmniCorp provides great tools. OmniCorp is the best.",
        "set2.zip_docA.txt": b"Footer of OmniCorp doc."
    }

    with zipfile.ZipFile(zip_path, "r") as zf:
        actual_files = zf.namelist()
        assert set(actual_files) == set(expected_files.keys()), f"Zip contents do not match expected files. Found: {actual_files}"

        for filename, expected_content in expected_files.items():
            with zf.open(filename) as f:
                content = f.read()
                assert content == expected_content, f"Content of {filename} does not match expected output."


def test_migration_log():
    log_path = "/home/user/migration.log"
    assert os.path.exists(log_path), f"Expected {log_path} to exist."

    with open(log_path, "r", encoding="utf-8") as f:
        log_content = f.read()

    expected_line = "Migration complete. Processed 3 valid documents."
    assert expected_line in log_content, f"Expected log line '{expected_line}' not found in {log_path}."


def test_script_uses_atomic_rename():
    script_path = "/home/user/migrate_docs.py"
    assert os.path.exists(script_path), f"Expected script {script_path} to exist."

    with open(script_path, "r", encoding="utf-8") as f:
        script_content = f.read()

    has_atomic = any(func in script_content for func in ["os.replace", "os.rename", "shutil.move"])
    assert has_atomic, "Script does not appear to use an atomic rename operation (os.replace, os.rename, or shutil.move)."


def _zip_bytes(entries):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, content in entries.items():
            zf.writestr(name, content)
    return output.getvalue()


def test_script_executes_on_unseen_archive_and_atomically_finalizes():
    script_path = "/home/user/migrate_docs.py"
    legacy_path = "/home/user/legacy_docs.tar"
    output_path = "/home/user/clean_docs.zip"
    temp_path = "/home/user/clean_docs_temp.zip"
    log_path = "/home/user/migration.log"
    tracked = [legacy_path, output_path, temp_path, log_path]
    backups = {}
    for path in tracked:
        backups[path] = open(path, "rb").read() if os.path.isfile(path) else None

    token = secrets.token_hex(8)
    zip1 = f"batch_{token}.zip"
    zip2 = f"notes_{token}.zip"
    doc1 = f"guide_{token}.txt"
    doc2 = f"repeat_{token}.md"
    doc3 = f"unicode_{token}.txt"
    bad1 = f"wrong_header_{token}.txt"
    bad2 = f"plain_{token}.txt"

    expected = {
        f"{zip1}_{doc1}": f"A fresh {token} document for OmniCorp.".encode("utf-8"),
        f"{zip1}_{doc2}": b"OmniCorp then OmniCorp; similar [company_v1] stays.",
        f"{zip2}_{doc3}": f"Unicode caf\u00e9 {token} belongs to OmniCorp.".encode("utf-8"),
    }

    archive1 = _zip_bytes({
        doc1: b"TECHDOC\x00" + f"A fresh {token} document for [COMPANY_V1].".encode("utf-8"),
        doc2: b"TECHDOC\x00[COMPANY_V1] then [COMPANY_V1]; similar [company_v1] stays.",
        bad1: b"TECHDOC!This must not be included.",
    })
    archive2 = _zip_bytes({
        doc3: b"TECHDOC\x00" + f"Unicode caf\u00e9 {token} belongs to [COMPANY_V1].".encode("utf-8"),
        bad2: b"ordinary data mentioning [COMPANY_V1] without the header",
    })

    runner_path = f"/tmp/migration_runner_{token}.py"
    record_path = f"/tmp/atomic_calls_{token}.json"
    runner = r'''import hashlib
import json
import os
import runpy
import shutil
import sys
import tarfile
import zipfile

script, record = sys.argv[1], sys.argv[2]
calls = []
real_replace = os.replace
real_rename = os.rename
real_move = shutil.move

def digest(path):
    try:
        with open(path, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except (OSError, TypeError):
        return None

def wrap(kind, func):
    def called(src, dst, *args, **kwargs):
        result = func(src, dst, *args, **kwargs)
        calls.append({"kind": kind, "src": os.fsdecode(src), "dst": os.fsdecode(dst), "digest": digest(dst)})
        return result
    return called

os.replace = wrap("os.replace", real_replace)
os.rename = wrap("os.rename", real_rename)
shutil.move = wrap("shutil.move", real_move)

def no_extract(*args, **kwargs):
    raise AssertionError("Archive extraction to disk is forbidden; read members through archive APIs")

zipfile.ZipFile.extract = no_extract
zipfile.ZipFile.extractall = no_extract
tarfile.TarFile.extract = no_extract
tarfile.TarFile.extractall = no_extract
sys.argv = [script]
try:
    runpy.run_path(script, run_name="__main__")
finally:
    with open(record, "w", encoding="utf-8") as f:
        json.dump(calls, f)
'''

    try:
        tar_buffer = io.BytesIO()
        with tarfile.open(fileobj=tar_buffer, mode="w") as tf:
            for name, data in [(zip1, archive1), (zip2, archive2), (f"ignore_{token}.bin", b"not a zip")]:
                info = tarfile.TarInfo(name)
                info.size = len(data)
                tf.addfile(info, io.BytesIO(data))
        with open(legacy_path, "wb") as f:
            f.write(tar_buffer.getvalue())

        for path in (output_path, temp_path, log_path, record_path):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
        with open(runner_path, "w", encoding="utf-8") as f:
            f.write(runner)

        result = subprocess.run(
            ["python3", runner_path, script_path, record_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"Migration script failed on an unseen archive.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        assert zipfile.is_zipfile(output_path), "Script did not create a valid clean_docs.zip when executed."

        with zipfile.ZipFile(output_path, "r") as zf:
            assert set(zf.namelist()) == set(expected), f"Unexpected files for unseen input: {zf.namelist()}"
            for name, content in expected.items():
                assert zf.read(name) == content, f"Incorrect transformed content for {name}."

        expected_line = "Migration complete. Processed 3 valid documents."
        with open(log_path, "r", encoding="utf-8") as f:
            assert expected_line in f.read().splitlines(), "Dynamic run did not append the correct summary."

        with open(output_path, "rb") as f:
            final_digest = hashlib.sha256(f.read()).hexdigest()
        with open(record_path, "r", encoding="utf-8") as f:
            calls = json.load(f)
        atomic_calls = [
            call for call in calls
            if os.path.abspath(call["dst"]) == output_path
            and os.path.abspath(call["src"]) != output_path
            and call.get("digest") == final_digest
        ]
        assert atomic_calls, "The executed script did not successfully atomically rename/move the completed archive into clean_docs.zip."
    finally:
        for path, data in backups.items():
            if data is None:
                try:
                    os.unlink(path)
                except FileNotFoundError:
                    pass
            else:
                with open(path, "wb") as f:
                    f.write(data)
        for path in (runner_path, record_path):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
