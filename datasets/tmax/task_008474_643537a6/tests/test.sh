#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import struct
import subprocess
import tarfile
import tempfile

WORKSPACE_DIR = "/home/user/workspace"
INCLUDE_DIR = os.path.join(WORKSPACE_DIR, "include")
FINAL_BIN = "/home/user/final.bin"
PACK_CPP = "/home/user/pack.cpp"
PACK_BIN = "/home/user/pack"
LEGACY_TAR = "/home/user/legacy_project.tar"

EXPECTED_FILES = ["main.cpp", "utils.cpp", "utils.h"]


def expected_contents():
    expected = {}
    with tarfile.open(LEGACY_TAR, "r") as archive:
        for member in archive.getmembers():
            name = os.path.basename(member.name)
            if member.isfile() and name in EXPECTED_FILES:
                raw = archive.extractfile(member).read()
                text = raw.decode("iso-8859-1").replace("OLD_MACRO_XYZ", "NEW_MACRO_ABC")
                expected[name] = text.encode("utf-8")
    assert sorted(expected) == sorted(EXPECTED_FILES), "Legacy archive does not contain the expected sources."
    return expected


def parse_archive(path):
    assert os.path.isfile(path), f"{path} is missing."
    with open(path, "rb") as f:
        data = f.read()

    offset = 0
    parsed_files = []
    while offset < len(data):
        if offset + 1 > len(data):
            raise AssertionError("Unexpected end of file while reading filename length.")
        name_len = data[offset]
        offset += 1

        if offset + name_len > len(data):
            raise AssertionError("Unexpected end of file while reading filename.")
        try:
            filename = data[offset:offset + name_len].decode("ascii")
        except UnicodeDecodeError as exc:
            raise AssertionError("Archive filename is not ASCII.") from exc
        offset += name_len

        if offset + 4 > len(data):
            raise AssertionError("Unexpected end of file while reading file size.")
        file_size = struct.unpack("<I", data[offset:offset + 4])[0]
        offset += 4

        if offset + file_size > len(data):
            raise AssertionError("Unexpected end of file while reading file contents.")
        file_content = data[offset:offset + file_size]
        offset += file_size
        parsed_files.append((filename, file_content))

    return parsed_files


def assert_archive_is_correct(path):
    parsed_files = parse_archive(path)
    filenames = [item[0] for item in parsed_files]
    assert filenames == sorted(filenames), f"Files in {path} are not in alphabetical order. Found: {filenames}"
    expected_filenames = sorted(EXPECTED_FILES)
    assert filenames == expected_filenames, f"Expected files {expected_filenames} in {path}, but got {filenames}."

    expected = expected_contents()
    for filename, content in parsed_files:
        assert content == expected[filename], f"Content of {filename} in {path} is not the fully transformed legacy source."


def run_packer_and_require_correct_archive(executable):
    errors = []
    for cwd in ("/home/user", WORKSPACE_DIR):
        try:
            if os.path.lexists(FINAL_BIN):
                os.unlink(FINAL_BIN)
            result = subprocess.run(
                [executable], cwd=cwd, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, timeout=15, check=False
            )
            if result.returncode != 0:
                errors.append(f"cwd={cwd}: exit status {result.returncode}")
                continue
            try:
                assert_archive_is_correct(FINAL_BIN)
                return
            except AssertionError as exc:
                errors.append(f"cwd={cwd}: {exc}")
        except (OSError, subprocess.TimeoutExpired) as exc:
            errors.append(f"cwd={cwd}: {exc}")
    raise AssertionError("Packer did not generate a correct final.bin when executed: " + "; ".join(errors))


def test_workspace_and_files():
    assert os.path.isdir(WORKSPACE_DIR), f"Directory {WORKSPACE_DIR} does not exist."
    for f in EXPECTED_FILES:
        file_path = os.path.join(WORKSPACE_DIR, f)
        assert os.path.isfile(file_path), f"File {file_path} is missing."


def test_workspace_preserves_complete_transformed_sources():
    expected = expected_contents()
    for filename in EXPECTED_FILES:
        path = os.path.join(WORKSPACE_DIR, filename)
        with open(path, "rb") as f:
            actual = f.read()
        assert actual == expected[filename], f"{filename} is not the complete converted and macro-updated source from the legacy archive."


def test_file_encoding_and_macros():
    main_cpp_path = os.path.join(WORKSPACE_DIR, "main.cpp")
    with open(main_cpp_path, "rb") as f:
        content = f.read()
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError:
        raise AssertionError("main.cpp is not valid UTF-8.")
    assert "NEW_MACRO_ABC" in text, "NEW_MACRO_ABC not found in main.cpp."
    assert "OLD_MACRO_XYZ" not in text, "OLD_MACRO_XYZ still present in main.cpp."
    assert "©" in text, "Copyright symbol not properly decoded as UTF-8 in main.cpp."

    utils_h_path = os.path.join(WORKSPACE_DIR, "utils.h")
    with open(utils_h_path, "rb") as f:
        content = f.read()
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError:
        raise AssertionError("utils.h is not valid UTF-8.")
    assert "NEW_MACRO_ABC" in text, "NEW_MACRO_ABC not found in utils.h."
    assert "OLD_MACRO_XYZ" not in text, "OLD_MACRO_XYZ still present in utils.h."
    assert "Función" in text, "Special character not properly decoded as UTF-8 in utils.h."

    utils_cpp_path = os.path.join(WORKSPACE_DIR, "utils.cpp")
    with open(utils_cpp_path, "rb") as f:
        content = f.read()
    try:
        text = content.decode("utf-8")
    except UnicodeDecodeError:
        raise AssertionError("utils.cpp is not valid UTF-8.")
    assert "Más" in text, "Special character not properly decoded as UTF-8 in utils.cpp."


def test_symlinks():
    assert os.path.isdir(INCLUDE_DIR), f"Directory {INCLUDE_DIR} does not exist."
    symlink_path = os.path.join(INCLUDE_DIR, "utils.h")
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link."
    target = os.readlink(symlink_path)
    abs_target = os.path.abspath(os.path.join(INCLUDE_DIR, target))
    expected_target = os.path.join(WORKSPACE_DIR, "utils.h")
    assert abs_target == expected_target, f"Symlink {symlink_path} points to {abs_target}, expected {expected_target}."


def test_packer_source_and_executable_generate_archive():
    assert os.path.isfile(PACK_CPP) and not os.path.islink(PACK_CPP), f"{PACK_CPP} is missing or is not a regular source file."
    assert os.path.isfile(PACK_BIN) and not os.path.islink(PACK_BIN), f"{PACK_BIN} is missing or is not a regular compiled file."
    assert os.access(PACK_BIN, os.X_OK), f"{PACK_BIN} is not executable."
    with open(PACK_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{PACK_BIN} is not a compiled ELF executable."

    # Exercise the submitted compiled artifact and verify what it actually creates.
    run_packer_and_require_correct_archive(PACK_BIN)

    # Compile and exercise pack.cpp independently, ensuring the submitted source
    # itself implements the required packer rather than merely accompanying it.
    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "pack")
        result = subprocess.run(
            ["g++", "-std=c++17", PACK_CPP, "-o", rebuilt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, check=False
        )
        assert result.returncode == 0, "pack.cpp does not compile: " + result.stderr.decode("utf-8", "replace")
        run_packer_and_require_correct_archive(rebuilt)


def test_final_bin_format():
    assert os.path.isfile(FINAL_BIN), f"{FINAL_BIN} is missing."
    parsed_files = parse_archive(FINAL_BIN)

    filenames = [f[0] for f in parsed_files]
    assert filenames == sorted(filenames), f"Files in {FINAL_BIN} are not in alphabetical order. Found: {filenames}"

    expected_filenames = sorted(EXPECTED_FILES)
    assert filenames == expected_filenames, f"Expected files {expected_filenames} in {FINAL_BIN}, but got {filenames}."

    for filename, content in parsed_files:
        workspace_file = os.path.join(WORKSPACE_DIR, filename)
        with open(workspace_file, "rb") as f:
            expected_content = f.read()
        assert content == expected_content, f"Content of {filename} in {FINAL_BIN} does not match the file in workspace."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
