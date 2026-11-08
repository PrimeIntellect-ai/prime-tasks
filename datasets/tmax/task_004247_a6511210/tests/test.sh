#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import io
import json
import os
import re
import subprocess
import tarfile
import tempfile

ARCHIVE = "/home/user/normalized_configs.tar.gz"
INPUT_ARCHIVE = "/home/user/legacy_configs.tar.gz"


def test_normalized_configs_archive_exists():
    archive_path = ARCHIVE
    assert os.path.exists(archive_path), f"Missing final archive: {archive_path}"
    assert os.path.isfile(archive_path), f"Path is not a file: {archive_path}"
    assert tarfile.is_tarfile(archive_path), f"File is not a valid tar archive: {archive_path}"


def test_normalized_configs_contents_and_manifest():
    archive_path = ARCHIVE
    assert os.path.exists(archive_path), f"Archive {archive_path} does not exist."

    expected_files = {
        "prod_v1.2.4_db_settings.json",
        "staging_v2.0.0_api_limits.json",
        "dev_v3.1.0_feature_flags.csv",
        "manifest.sha256"
    }

    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(archive_path, "r:gz") as tar:
            tar.extractall(path=tmpdir)

        extracted_files = set(os.listdir(tmpdir))

        for expected_file in expected_files:
            assert expected_file in extracted_files, f"Expected file '{expected_file}' not found in the archive."

        manifest_path = os.path.join(tmpdir, "manifest.sha256")
        assert os.path.exists(manifest_path), "manifest.sha256 is missing."

        result = subprocess.run(
            ["sha256sum", "-c", "manifest.sha256"],
            cwd=tmpdir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        assert result.returncode == 0, f"sha256sum verification failed:\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"


def _root_regular_files(path):
    result = {}
    with tarfile.open(path, "r:gz") as archive:
        for member in archive.getmembers():
            name = member.name
            while name.startswith("./"):
                name = name[2:]
            if name in ("", ".") and member.isdir():
                continue
            assert not member.name.startswith("/"), f"Absolute archive path: {member.name}"
            assert name and "/" not in name and name not in (".", ".."), f"Archive entry is not at its root: {member.name}"
            assert member.isfile(), f"Non-regular archive entry: {member.name}"
            assert name not in result, f"Duplicate archive entry: {name}"
            result[name] = archive.extractfile(member).read()
    return result


def _expected_from_input(path):
    expected = {}
    with tarfile.open(path, "r:gz") as archive:
        for member in archive.getmembers():
            if not member.isfile():
                continue
            original = os.path.basename(member.name)
            data = archive.extractfile(member).read()
            if original.endswith(".json"):
                parsed = json.loads(data.decode("utf-8"))
                env = str(parsed["metadata"]["env"])
                version = str(parsed["metadata"]["version"])
            elif original.endswith(".csv"):
                rows = list(csv.reader(io.StringIO(data.decode("utf-8"))))
                assert len(rows) >= 2 and rows[0][:2] == ["env", "version"]
                env, version = rows[1][0], rows[1][1]
            else:
                continue
            expected[f"{env}_{version}_{original}"] = data
    return expected


def test_archive_preserves_all_input_files_and_has_exact_manifest():
    expected = _expected_from_input(INPUT_ARCHIVE)
    actual = _root_regular_files(ARCHIVE)
    assert set(actual) == set(expected) | {"manifest.sha256"}, "Archive has missing or unexpected entries"
    for name, data in expected.items():
        assert actual[name] == data, f"Contents were not preserved for {name}"

    manifest = actual["manifest.sha256"].decode("utf-8").splitlines()
    entries = {}
    for line in manifest:
        match = re.fullmatch(r"([0-9a-f]{64})  ([^/]+)", line)
        assert match, f"Invalid manifest line: {line!r}"
        digest, name = match.groups()
        assert name not in entries, f"Duplicate manifest entry: {name}"
        entries[name] = digest
    assert set(entries) == set(expected), "Manifest does not list exactly the renamed configuration files"
    for name, data in expected.items():
        assert entries[name] == hashlib.sha256(data).hexdigest(), f"Wrong manifest hash for {name}"
TEST_EOF

cat << 'PROBE_EOF' > /tmp/test_dynamic_probe.py
import csv
import hashlib
import io
import json
import os
import pathlib
import re
import secrets
import shutil
import subprocess
import tarfile
import tempfile

home = pathlib.Path("/home/user")
input_archive = home / "legacy_configs.tar.gz"
output_archive = home / "normalized_configs.tar.gz"
processing = home / "processing"
executable = home / ".config_manager_verifier"
original_archive = input_archive.read_bytes()

token = secrets.token_hex(8)
files = {
    f"service_{token}.json": json.dumps({
        "metadata": {"env": f"qa{token}", "version": f"v7.{token[:4]}"},
        "payload": {"token": token, "enabled": True}
    }, indent=2).encode() + b"\n",
    f"limits_{token}.json": json.dumps({
        "metadata": {"env": f"edge{token}", "version": f"r{token[4:]}"},
        "limit": 7319
    }, indent=2).encode() + b"\n",
    f"flags_{token}.csv": (
        "env,version,flag,enabled\n"
        f"dev{token},build{token[:6]},random_feature,true\n"
        f"dev{token},build{token[:6]},other_feature,false\n"
    ).encode(),
    f"routes_{token}.csv": (
        "env,version,path,target\n"
        f"prod{token},release{token[2:8]},/dynamic,backend-{token}\n"
    ).encode(),
}

expected = {}
for name, data in files.items():
    if name.endswith(".json"):
        obj = json.loads(data.decode())
        env, version = str(obj["metadata"]["env"]), str(obj["metadata"]["version"])
    else:
        rows = list(csv.reader(io.StringIO(data.decode())))
        assert rows[0][:2] == ["env", "version"]
        env, version = rows[1][0], rows[1][1]
    expected[f"{env}_{version}_{name}"] = data

try:
    with tempfile.TemporaryDirectory() as source_dir:
        source = pathlib.Path(source_dir)
        for name, data in files.items():
            (source / name).write_bytes(data)
        with tarfile.open(input_archive, "w:gz") as archive:
            for name in files:
                archive.add(source / name, arcname=name)

    shutil.rmtree(processing, ignore_errors=True)
    output_archive.unlink(missing_ok=True)
    run = subprocess.run([str(executable)], cwd=home, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30)
    assert run.returncode == 0, f"Program failed on dynamic input:\nSTDOUT:\n{run.stdout}\nSTDERR:\n{run.stderr}"
    assert output_archive.is_file() and tarfile.is_tarfile(output_archive), "Program did not create a valid dynamic output archive"

    actual = {}
    with tarfile.open(output_archive, "r:gz") as archive:
        for member in archive.getmembers():
            name = member.name
            while name.startswith("./"):
                name = name[2:]
            if name in ("", ".") and member.isdir():
                continue
            assert not member.name.startswith("/"), f"Absolute path in archive: {member.name}"
            assert name and "/" not in name and name not in (".", ".."), f"Entry is not at archive root: {member.name}"
            assert member.isfile(), f"Non-regular archive entry: {member.name}"
            assert name not in actual, f"Duplicate archive entry: {name}"
            actual[name] = archive.extractfile(member).read()

    assert set(actual) == set(expected) | {"manifest.sha256"}, "Dynamic archive has missing or unexpected files"
    for name, data in expected.items():
        assert actual[name] == data, f"Dynamic input contents were not preserved for {name}"

    entries = {}
    for line in actual["manifest.sha256"].decode("utf-8").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  ([^/]+)", line)
        assert match, f"Invalid dynamic manifest line: {line!r}"
        digest, name = match.groups()
        assert name not in entries, f"Duplicate dynamic manifest entry: {name}"
        entries[name] = digest
    assert set(entries) == set(expected), "Dynamic manifest does not list exactly the processed files"
    for name, data in expected.items():
        assert entries[name] == hashlib.sha256(data).hexdigest(), f"Wrong dynamic hash for {name}"
finally:
    input_archive.write_bytes(original_archive)
PROBE_EOF

run_checks() {
    test -f /home/user/config_manager.cpp || return 1
    test ! -L /home/user/config_manager.cpp || return 1
    test -s /home/user/config_manager.cpp || return 1

    g++ -std=c++17 -I/home/user /home/user/config_manager.cpp -o /home/user/.config_manager_verifier || return 1

    rm -rf /home/user/processing
    rm -f /home/user/normalized_configs.tar.gz
    timeout 30 /home/user/.config_manager_verifier || return 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    python3 /tmp/test_dynamic_probe.py || return 1

    # Restore the required final artifact for the original supplied archive.
    rm -rf /home/user/processing
    rm -f /home/user/normalized_configs.tar.gz
    timeout 30 /home/user/.config_manager_verifier || return 1
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1
}

if run_checks 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
