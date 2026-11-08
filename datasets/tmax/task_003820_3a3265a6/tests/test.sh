#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import shutil
import signal
import subprocess
import tarfile
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/safe_archive.sh"
SOURCE_PATH = "/home/user/app_configs"
BACKUP_PATH = "/home/user/config_backup.tar.gz.b64"
LOG_PATH = "/home/user/archive_log.txt"


def test_script_exists():
    script_path = SCRIPT_PATH
    assert os.path.isfile(script_path), f"Script missing: {script_path}"
    # Retain the original file assertion and also ensure it can be parsed as a Bash script.
    result = subprocess.run(
        ["bash", "-n", script_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0, f"Script is not valid Bash: {result.stderr}"


def test_archive_log_contents():
    log_path = LOG_PATH
    assert os.path.exists(log_path), f"Log file missing: {log_path}"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected = [
        "config.yml",
        "ext_link.conf",
        "huge_routing.conf.part_aa",
        "huge_routing.conf.part_ab",
        "huge_routing.conf.part_ac",
        "settings.json",
    ]
    assert lines == expected, f"Log file contents do not match exactly. Expected {expected}, got {lines}"


def test_backup_archive_contents():
    backup_path = BACKUP_PATH
    assert os.path.exists(backup_path), f"Backup file missing: {backup_path}"

    temp_dir = tempfile.mkdtemp()
    try:
        b64_decoded_path = os.path.join(temp_dir, "backup.tar.gz")
        with open(backup_path, "rb") as f_in, open(b64_decoded_path, "wb") as f_out:
            try:
                base64.decode(f_in, f_out)
            except Exception as e:
                pytest.fail(f"Failed to decode base64 from {backup_path}: {e}")

        try:
            with tarfile.open(b64_decoded_path, "r:gz") as tar:
                tar.extractall(path=temp_dir)
        except tarfile.TarError as e:
            pytest.fail(f"Failed to open or extract tar.gz file: {e}")

        extracted_files = []
        for root, dirs, files in os.walk(temp_dir):
            if root == temp_dir and "backup.tar.gz" in files:
                files.remove("backup.tar.gz")
            for f in files:
                extracted_files.append(f)

        expected = {
            "config.yml",
            "ext_link.conf",
            "huge_routing.conf.part_aa",
            "huge_routing.conf.part_ab",
            "huge_routing.conf.part_ac",
            "settings.json",
        }
        assert set(extracted_files) == expected, (
            f"Extracted files do not match expected set. Expected {expected}, "
            f"got {set(extracted_files)}"
        )

        orig_large_file = "/home/user/app_configs/app3/huge_routing.conf"
        with open(orig_large_file, "rb") as f:
            orig_data = f.read()

        chunk_aa = None
        chunk_ab = None
        chunk_ac = None
        for root, dirs, files in os.walk(temp_dir):
            if "huge_routing.conf.part_aa" in files:
                chunk_aa = os.path.join(root, "huge_routing.conf.part_aa")
            if "huge_routing.conf.part_ab" in files:
                chunk_ab = os.path.join(root, "huge_routing.conf.part_ab")
            if "huge_routing.conf.part_ac" in files:
                chunk_ac = os.path.join(root, "huge_routing.conf.part_ac")

        assert chunk_aa and chunk_ab and chunk_ac, (
            "One or more huge_routing.conf chunks are missing from the extracted archive."
        )

        with open(chunk_aa, "rb") as f:
            data_aa = f.read()
        with open(chunk_ab, "rb") as f:
            data_ab = f.read()
        with open(chunk_ac, "rb") as f:
            data_ac = f.read()

        assert len(data_aa) == 1048576, f"part_aa size is {len(data_aa)}, expected 1048576 (1MB)"
        assert len(data_ab) == 1048576, f"part_ab size is {len(data_ab)}, expected 1048576 (1MB)"
        reconstructed = data_aa + data_ab + data_ac
        assert reconstructed == orig_data, "Reconstructed huge_routing.conf does not match the original file data."

        for fname, orig_path in [
            ("config.yml", "/home/user/app_configs/app1/config.yml"),
            ("settings.json", "/home/user/app_configs/app2/settings.json"),
            ("ext_link.conf", "/home/user/external_configs/ext.conf"),
        ]:
            extracted_path = None
            for root, dirs, files in os.walk(temp_dir):
                if fname in files:
                    extracted_path = os.path.join(root, fname)
                    break
            assert extracted_path, f"File {fname} not found in extracted archive."
            with open(orig_path, "rb") as f_orig, open(extracted_path, "rb") as f_ext:
                assert f_orig.read() == f_ext.read(), f"Contents of {fname} do not match the original."
    finally:
        shutil.rmtree(temp_dir)


def run_script_with_timeout(timeout=20):
    proc = subprocess.Popen(
        ["bash", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        stdout, stderr = proc.communicate()
        pytest.fail(f"Script did not terminate while traversing symbolic-link cycles. stdout={stdout!r}, stderr={stderr!r}")
    assert proc.returncode == 0, f"Script execution failed with code {proc.returncode}. stdout={stdout!r}, stderr={stderr!r}"


def read_flat_archive(path):
    assert os.path.isfile(path), f"Backup file missing after executing script: {path}"
    with open(path, "rb") as f:
        encoded = f.read()
    try:
        compressed = base64.decodebytes(encoded)
    except Exception as e:
        pytest.fail(f"Generated backup is not valid base64: {e}")

    result = {}
    try:
        with tarfile.open(fileobj=__import__("io").BytesIO(compressed), mode="r:gz") as tar:
            for member in tar.getmembers():
                normalized = member.name
                while normalized.startswith("./"):
                    normalized = normalized[2:]
                if member.isdir() and normalized in ("", "."):
                    continue
                assert member.isfile(), f"Archive contains a non-regular entry: {member.name}"
                assert normalized and "/" not in normalized, f"Archive is not flat: {member.name}"
                assert normalized not in result, f"Archive contains duplicate entry: {normalized}"
                stream = tar.extractfile(member)
                assert stream is not None
                result[normalized] = stream.read()
    except (tarfile.TarError, OSError) as e:
        pytest.fail(f"Generated backup is not a valid gzip-compressed tar archive: {e}")
    return result


def test_script_executes_on_varied_tree_and_handles_cycles():
    token = uuid.uuid4().hex[:12]
    source_saved = f"/home/user/.app_configs_saved_{token}"
    external = f"/home/user/.dynamic_external_{token}"
    saved_outputs = {}

    names = {
        "small": f"small_{token}.ini",
        "below": f"below_{token}.dat",
        "exact": f"exact_{token}.bin",
        "large": f"large_{token}.bin",
        "external_link": f"external_link_{token}.conf",
        "external_target": f"target_{token}.conf",
    }
    data = {
        "small": (f"dynamic-small-{token}\n").encode(),
        "below": os.urandom(1048575),
        "exact": os.urandom(1048576),
        "large": os.urandom(2 * 1048576 + 137),
        "external": (f"dynamic-external-{token}\n").encode(),
    }

    try:
        os.rename(SOURCE_PATH, source_saved)
        for output in (BACKUP_PATH, LOG_PATH):
            if os.path.lexists(output):
                saved = f"{output}.saved_{token}"
                os.rename(output, saved)
                saved_outputs[output] = saved

        os.makedirs(os.path.join(SOURCE_PATH, "nested", "deeper"))
        os.makedirs(external)
        with open(os.path.join(SOURCE_PATH, "nested", names["small"]), "wb") as f:
            f.write(data["small"])
        with open(os.path.join(SOURCE_PATH, names["below"]), "wb") as f:
            f.write(data["below"])
        with open(os.path.join(SOURCE_PATH, "nested", "deeper", names["exact"]), "wb") as f:
            f.write(data["exact"])
        with open(os.path.join(SOURCE_PATH, names["large"]), "wb") as f:
            f.write(data["large"])
        with open(os.path.join(external, names["external_target"]), "wb") as f:
            f.write(data["external"])

        # The external directory links back to the source, creating a real directory cycle.
        os.symlink(external, os.path.join(SOURCE_PATH, "nested", "external_dir_link"))
        os.symlink(SOURCE_PATH, os.path.join(external, "back_to_source"))
        # Also exercise following a symbolic link directly to a regular file.
        os.symlink(
            os.path.join(external, names["external_target"]),
            os.path.join(SOURCE_PATH, names["external_link"]),
        )

        run_script_with_timeout()

        expected = {
            names["small"]: data["small"],
            names["below"]: data["below"],
            names["exact"] + ".part_aa": data["exact"],
            names["large"] + ".part_aa": data["large"][:1048576],
            names["large"] + ".part_ab": data["large"][1048576:2097152],
            names["large"] + ".part_ac": data["large"][2097152:],
            names["external_link"]: data["external"],
            names["external_target"]: data["external"],
        }

        archived = read_flat_archive(BACKUP_PATH)
        assert archived == expected, (
            f"Archive produced from varied input is incorrect. Expected entries "
            f"{sorted(expected)}, got {sorted(archived)}"
        )

        assert os.path.isfile(LOG_PATH), "Log file missing after executing script"
        with open(LOG_PATH, "r") as f:
            logged = [line.rstrip("\n") for line in f]
        assert logged == sorted(expected), f"Dynamic log is not the exact sorted archive list: {logged}"
    finally:
        if os.path.lexists(SOURCE_PATH):
            shutil.rmtree(SOURCE_PATH)
        if os.path.lexists(external):
            shutil.rmtree(external)
        if os.path.lexists(source_saved):
            os.rename(source_saved, SOURCE_PATH)
        for output in (BACKUP_PATH, LOG_PATH):
            if os.path.lexists(output):
                os.remove(output)
            if output in saved_outputs and os.path.lexists(saved_outputs[output]):
                os.rename(saved_outputs[output], output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
