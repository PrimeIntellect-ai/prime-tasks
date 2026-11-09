#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import subprocess
import tarfile

ARCHIVE_DIR = "/home/user/config_archive"
UTF8_PATH = os.path.join(ARCHIVE_DIR, "system_master_utf8.ini")


def archive_source_bytes():
    archive = os.path.join(ARCHIVE_DIR, "legacy_configs.tar.gz")
    assert os.path.isfile(archive), f"Archive {archive} does not exist."
    with tarfile.open(archive, "r:gz") as tf:
        member = tf.extractfile("system_master.ini")
        assert member is not None, "Archive does not contain system_master.ini."
        return member.read()


def expected_chunks(data):
    chunks = []
    current = None
    for line in data.splitlines(keepends=True):
        if line.startswith(b"[MODULE_"):
            current = bytearray()
            chunks.append(current)
        if current is not None:
            current.extend(line)
    return [bytes(chunk) for chunk in chunks]


def clear_modules():
    for path in glob.glob(os.path.join(ARCHIVE_DIR, "module_*.ini")):
        os.unlink(path)


def assert_generated_chunks(input_data):
    expected = expected_chunks(input_data)
    expected_names = [f"module_{i:02d}.ini" for i in range(len(expected))]
    actual_names = sorted(os.path.basename(p) for p in glob.glob(os.path.join(ARCHIVE_DIR, "module_*.ini")))
    assert actual_names == expected_names, f"Generated module files differ: {actual_names} != {expected_names}"

    for name, wanted in zip(expected_names, expected):
        path = os.path.join(ARCHIVE_DIR, name)
        assert os.path.isfile(path), f"Generated module {path} is missing."
        with open(path, "rb") as f:
            actual = f.read()
        assert actual == wanted, f"Generated module {path} has incorrect content."
        actual.decode("utf-8")


def run_splitter(executable, input_data):
    with open(UTF8_PATH, "wb") as f:
        f.write(input_data)
    clear_modules()
    result = subprocess.run(
        [executable], cwd="/tmp", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=10, check=False
    )
    assert result.returncode == 0, (
        f"Splitter {executable} exited with {result.returncode}: "
        f"{result.stderr.decode('utf-8', errors='replace')}"
    )
    assert_generated_chunks(input_data)


def test_system_master_utf8():
    path = UTF8_PATH
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "rb") as f:
        content = f.read()

    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError:
        assert False, f"File {path} is not valid UTF-8."

    assert "[MODULE_ALPHA]" in text, f"File {path} missing expected content."
    assert "café" in text, f"File {path} missing expected UTF-8 characters."

    source = archive_source_bytes()
    expected = source.decode("iso-8859-1").encode("utf-8")
    assert content == expected, f"File {path} is not the exact UTF-8 conversion of the archived source."

    extracted = os.path.join(ARCHIVE_DIR, "system_master.ini")
    assert os.path.isfile(extracted), f"Extracted file {extracted} does not exist."
    with open(extracted, "rb") as f:
        assert f.read() == source, f"Extracted file {extracted} differs from the archive member."


def test_split_config_executable():
    c_file = "/home/user/split_config.c"
    bin_file = "/home/user/split_config"

    assert os.path.isfile(c_file), f"C source file {c_file} does not exist."
    assert os.path.isfile(bin_file), f"Executable {bin_file} does not exist."
    assert os.access(bin_file, os.X_OK), f"File {bin_file} is not executable."
    with open(bin_file, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {bin_file} is not a compiled ELF executable."

    rebuilt = "/tmp/split_config_rebuilt"
    compile_result = subprocess.run(
        ["gcc", c_file, "-o", rebuilt], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=20, check=False
    )
    assert compile_result.returncode == 0, (
        "split_config.c does not compile: "
        + compile_result.stderr.decode("utf-8", errors="replace")
    )

    with open(UTF8_PATH, "rb") as f:
        original_utf8 = f.read()

    nonce = secrets.token_hex(12)
    probe = (
        f"[MODULE_PROBE_{nonce}]\n"
        f"description=café-{nonce}\n"
        "status=inactive\n"
        " [MODULE_NOT_A_HEADER]\n"
        f"[MODULE_SECOND_{nonce}]\n"
        "status=active\n"
        f"value=façade-{nonce}\n"
        f"[MODULE_THIRD_{nonce}]\n"
        "status=suspended\n"
        f"value=piñata-{nonce}\n"
    ).encode("utf-8")

    try:
        run_splitter(bin_file, probe)
        run_splitter(rebuilt, probe)
    finally:
        with open(UTF8_PATH, "wb") as f:
            f.write(original_utf8)

    clear_modules()
    result = subprocess.run(
        [bin_file], cwd="/tmp", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=10, check=False
    )
    assert result.returncode == 0, (
        f"Splitter failed on system_master_utf8.ini: "
        f"{result.stderr.decode('utf-8', errors='replace')}"
    )
    assert_generated_chunks(original_utf8)


def test_active_configs_symlinks():
    active_dir = "/home/user/active_configs"
    assert os.path.isdir(active_dir), f"Directory {active_dir} does not exist."

    expected_symlinks = ["module_00.ini", "module_02.ini", "module_04.ini"]
    unexpected_symlinks = ["module_01.ini", "module_03.ini"]

    for sym in expected_symlinks:
        sym_path = os.path.join(active_dir, sym)
        assert os.path.islink(sym_path), f"Expected symlink {sym_path} does not exist or is not a symlink."
        target = os.readlink(sym_path)
        assert os.path.isabs(target), f"Symlink {sym_path} does not point to an absolute path."
        assert target == f"/home/user/config_archive/{sym}", f"Symlink {sym_path} points to incorrect target {target}."
        assert os.path.isfile(sym_path), f"Symlink {sym_path} is dangling or does not reference a module file."
        with open(sym_path, "r", encoding="utf-8") as f:
            assert any(line.rstrip("\r\n") == "status=active" for line in f), f"Symlink {sym_path} references a module not explicitly active."

    for sym in unexpected_symlinks:
        sym_path = os.path.join(active_dir, sym)
        assert not os.path.exists(sym_path), f"Unexpected symlink {sym_path} should not exist."
        assert not os.path.lexists(sym_path), f"Unexpected dangling entry {sym_path} should not exist."


def test_active_master_content():
    path = "/home/user/active_master.ini"
    assert os.path.isfile(path), f"File {path} does not exist."

    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
    except UnicodeDecodeError:
        assert False, f"File {path} is not valid UTF-8."

    expected_content = """[MODULE_ALPHA]
description=Legacy cache system
status=active
path=/var/cache/app
param1=café
[MODULE_GAMMA]
description=Network bridge
status=active
bridge_name=br0
note=façade
[MODULE_EPSILON]
description=Metrics aggregator
status=active
interval=60
tag=piñata
"""
    assert content.strip() == expected_content.strip(), f"Content of {path} does not match the expected active modules."

    linked_content = b""
    for name in sorted(["module_00.ini", "module_02.ini", "module_04.ini"]):
        with open(os.path.join("/home/user/active_configs", name), "rb") as f:
            linked_content += f.read()
    with open(path, "rb") as f:
        merged = f.read()
    merged.decode("utf-8")
    assert merged == linked_content, f"File {path} is not the exact alphabetical concatenation of the active symlinks."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
