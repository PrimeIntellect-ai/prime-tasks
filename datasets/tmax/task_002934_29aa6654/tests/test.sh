#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import stat
import subprocess
import tempfile
import uuid


def test_extracted_docs_directory_exists():
    """Test that the incoming_docs.tar.gz was extracted to the correct directory."""
    extracted_dir = "/home/user/extracted_docs"
    assert os.path.isdir(extracted_dir), f"The directory {extracted_dir} does not exist. Did you extract the archive?"
    assert os.path.isfile(os.path.join(extracted_dir, "doc_map.ini")), "doc_map.ini is missing from the extracted directory."


def test_doc_index_md_content():
    """Test that doc_index.md exists and contains the correct formatted output."""
    index_file = "/home/user/doc_index.md"
    assert os.path.exists(index_file), f"The file {index_file} does not exist."
    assert os.path.isfile(index_file), f"{index_file} is not a regular file."

    expected_content = (
        "- docs/api/v1.txt: API Version 1\n"
        "- docs/misc/readme.txt: General Readme\n"
    )

    with open(index_file, "r") as f:
        actual_content = f.read()

    actual_lines = [line.strip() for line in actual_content.strip().splitlines() if line.strip()]
    expected_lines = [line.strip() for line in expected_content.strip().splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"The content of {index_file} is incorrect.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Got:\n{chr(10).join(actual_lines)}"
    )


def _is_elf_executable(path):
    try:
        st = os.stat(path)
        if not stat.S_ISREG(st.st_mode) or not (st.st_mode & 0o111):
            return False
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def _write_dynamic_case(root):
    shutil.rmtree(root)
    os.makedirs(os.path.join(root, "generated", "nested"))

    token = uuid.uuid4().hex
    files = {
        "generated/zeta.txt": f"Zeta {token}\nsecond line\n".encode(),
        "generated/nested/alpha.txt": f"Alpha {token}\nignored body\n".encode(),
        "generated/wrong.txt": f"Wrong {token}\n".encode(),
        "generated/data.bin": f"Binary title {token}\n".encode(),
    }
    for rel, data in files.items():
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)

    manifest = [
        "[Docs]",
        f"one=generated/zeta.txt|{len(files['generated/zeta.txt'])}",
        f"two=generated/missing.txt|17",
        f"three=generated/data.bin|{len(files['generated/data.bin'])}",
        f"four=generated/wrong.txt|{len(files['generated/wrong.txt']) + 1}",
        f"five=generated/nested/alpha.txt|{len(files['generated/nested/alpha.txt'])}",
    ]
    with open(os.path.join(root, "doc_map.ini"), "w", newline="\n") as f:
        f.write("\n".join(manifest) + "\n")

    return [
        f"- generated/nested/alpha.txt: Alpha {token}",
        f"- generated/zeta.txt: Zeta {token}",
    ]


def _run_and_check(program, extracted_dir, index_file):
    expected_lines = _write_dynamic_case(extracted_dir)
    if os.path.exists(index_file):
        os.remove(index_file)

    result = subprocess.run(
        [program], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"{program} failed on a generated manifest with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(index_file), f"{program} did not generate {index_file}."
    with open(index_file, "r") as f:
        actual_lines = [line.strip() for line in f.read().strip().splitlines() if line.strip()]
    assert actual_lines == expected_lines, (
        "The C++ parser did not correctly enforce file sizes, filter .txt files, "
        "read titles, and sort generated input.\n"
        f"Expected: {expected_lines}\nGot: {actual_lines}"
    )


def test_cpp_program_exists_is_compiled_and_handles_generated_input():
    source = "/home/user/parser.cpp"
    extracted_dir = "/home/user/extracted_docs"
    index_file = "/home/user/doc_index.md"

    assert os.path.isfile(source), f"Required C++ source file {source} is missing."

    compiled_candidates = []
    for dirpath, dirnames, filenames in os.walk("/home/user"):
        if dirpath == extracted_dir or dirpath.startswith(extracted_dir + os.sep):
            dirnames[:] = []
            continue
        for name in filenames:
            path = os.path.join(dirpath, name)
            if _is_elf_executable(path):
                compiled_candidates.append(path)
    assert compiled_candidates, "No compiled ELF executable for parser.cpp was found under /home/user."

    preferred_names = {"parser": 0, "parser.out": 1, "a.out": 2, "doc_parser": 3}
    compiled_candidates.sort(key=lambda p: (preferred_names.get(os.path.basename(p), 100), -os.path.getmtime(p)))
    submitted_binary = compiled_candidates[0]

    build = subprocess.run(
        ["g++", source, "-o", "/tmp/verifier_built_parser"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert build.returncode == 0, f"parser.cpp does not compile successfully:\n{build.stderr}"

    backup_dir = tempfile.mkdtemp(prefix="extracted_docs_backup_")
    backup_tree = os.path.join(backup_dir, "tree")
    shutil.copytree(extracted_dir, backup_tree)
    had_index = os.path.isfile(index_file)
    original_index = None
    if had_index:
        with open(index_file, "rb") as f:
            original_index = f.read()

    try:
        _run_and_check(submitted_binary, extracted_dir, index_file)
        _run_and_check("/tmp/verifier_built_parser", extracted_dir, index_file)
    finally:
        shutil.rmtree(extracted_dir, ignore_errors=True)
        shutil.copytree(backup_tree, extracted_dir)
        if had_index:
            with open(index_file, "wb") as f:
                f.write(original_index)
        elif os.path.exists(index_file):
            os.remove(index_file)
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
