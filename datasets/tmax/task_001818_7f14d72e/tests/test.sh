#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import re
import tarfile
import zipfile
import pathlib
import secrets
import subprocess
import tempfile


def test_published_docs_directory_exists():
    dir_path = "/home/user/published_docs"
    assert os.path.exists(dir_path), f"The directory {dir_path} does not exist."
    assert os.path.isdir(dir_path), f"The path {dir_path} is not a directory."


def test_published_docs_files_and_contents():
    expected_files = {
        "section_01.md": "Welcome to [PUBLIC_RELEASE] part 1.",
        "section_02.md": "Advanced routing in [PUBLIC_RELEASE] part 2.",
        "section_03.md": "Troubleshooting the [PUBLIC_RELEASE] system."
    }

    dir_path = "/home/user/published_docs"

    for filename, expected_content in expected_files.items():
        file_path = os.path.join(dir_path, filename)
        assert os.path.exists(file_path), f"The file {file_path} is missing."
        assert os.path.isfile(file_path), f"The path {file_path} is not a file."

        with open(file_path, "r") as f:
            content = f.read()
            assert content == expected_content, f"Content of {file_path} is incorrect. Expected '{expected_content}', got '{content}'."


def test_migration_log():
    log_path = "/home/user/migration_log.txt"
    assert os.path.exists(log_path), f"The log file {log_path} does not exist."
    assert os.path.isfile(log_path), f"The path {log_path} is not a file."

    expected_lines = [
        "/home/user/published_docs/section_01.md",
        "/home/user/published_docs/section_02.md",
        "/home/user/published_docs/section_03.md"
    ]

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert lines == expected_lines, f"The contents of {log_path} are incorrect. Expected {expected_lines}, got {lines}."


def expected_from_nested_archive():
    archive = "/home/user/old_docs.tar.gz"
    assert os.path.isfile(archive), f"The source archive {archive} is missing."

    with tarfile.open(archive, "r:gz") as tf:
        zip_members = [m for m in tf.getmembers() if os.path.basename(m.name) == "internal_drafts.zip"]
        assert len(zip_members) == 1, "internal_drafts.zip was not found uniquely in the tar archive."
        extracted = tf.extractfile(zip_members[0])
        assert extracted is not None
        zip_data = extracted.read()

    expected = {}
    with zipfile.ZipFile(io.BytesIO(zip_data)) as zf:
        xrd_names = sorted(n for n in zf.namelist() if not n.endswith("/") and n.endswith(".xrd"))
        assert xrd_names, "No .xrd inputs were found in internal_drafts.zip."
        for member in xrd_names:
            base = os.path.basename(member)
            match = re.fullmatch(r"file_(.+)\.xrd", base)
            assert match, f"Unexpected input filename: {base}"
            decrypted = bytes(b ^ 0x2F for b in zf.read(member))
            modified = decrypted.replace(b"[CONFIDENTIAL_DRAFT]", b"[PUBLIC_RELEASE]")
            expected[f"section_{match.group(1)}.md"] = modified
    return expected


def test_outputs_are_derived_from_all_nested_xrd_inputs():
    expected = expected_from_nested_archive()
    output_dir = pathlib.Path("/home/user/published_docs")
    actual_names = sorted(p.name for p in output_dir.iterdir() if p.is_file() and p.suffix == ".md")
    assert actual_names == sorted(expected), f"Expected .md files {sorted(expected)}, got {actual_names}."

    for name, content in expected.items():
        assert (output_dir / name).read_bytes() == content, f"{name} was not correctly derived from its archived .xrd input."

    expected_log = [str(output_dir / name) for name in sorted(expected)]
    with open("/home/user/migration_log.txt", "r") as f:
        actual_log = [line.strip() for line in f if line.strip()]
    assert actual_log == expected_log, f"Migration log is not the sorted list of archive-derived outputs: {actual_log}"


def find_cpp_sources():
    roots = ["/home/user", "/root", "/tmp", "/opt", "/workspace"]
    sources = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {"published_docs", ".git", "__pycache__"}]
            for name in files:
                if pathlib.Path(name).suffix.lower() in {".cpp", ".cc", ".cxx"}:
                    path = os.path.join(current, name)
                    if path != __file__:
                        sources.append(path)
    return sorted(set(sources))


def contains_result(root, captured, wanted):
    if any(value in captured for value in wanted):
        return True
    for current, _, files in os.walk(root):
        for name in files:
            path = os.path.join(current, name)
            try:
                if os.path.getsize(path) <= 1024 * 1024:
                    data = pathlib.Path(path).read_bytes()
                    if any(value in data for value in wanted):
                        return True
            except (OSError, PermissionError):
                pass
    return False


def exercise_binary(binary, work, encrypted, confidential, public):
    input_file = os.path.join(work, "file_91.xrd")
    input_dir = os.path.join(work, "inputs")
    output_dir = os.path.join(work, "outputs")
    os.makedirs(input_dir, exist_ok=True)
    os.makedirs(output_dir, exist_ok=True)
    pathlib.Path(input_file).write_bytes(encrypted)
    pathlib.Path(os.path.join(input_dir, "file_91.xrd")).write_bytes(encrypted)

    commands = [
        ([binary, input_file, os.path.join(work, "section_91.md")], None),
        ([binary, input_file], None),
        ([binary, input_dir, output_dir], None),
        ([binary], encrypted),
        ([binary], None),
    ]
    env = os.environ.copy()
    env.update({
        "INPUT_FILE": input_file,
        "INPUT_DIR": input_dir,
        "OUTPUT_FILE": os.path.join(work, "env_output.md"),
        "OUTPUT_DIR": output_dir,
    })
    wanted = (confidential, public)
    for command, stdin_data in commands:
        try:
            result = subprocess.run(
                command, cwd=work, env=env, input=stdin_data,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                timeout=5, check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            continue
        if contains_result(work, result.stdout + result.stderr, wanted):
            return True
    return False


def test_cpp_program_exists_compiles_and_processes_unseen_xor_input():
    sources = find_cpp_sources()
    assert sources, "No C++ source file was left by the migration workflow."

    nonce = secrets.token_hex(16).encode("ascii")
    confidential = b"Verifier " + nonce + b" [CONFIDENTIAL_DRAFT] payload."
    public = confidential.replace(b"[CONFIDENTIAL_DRAFT]", b"[PUBLIC_RELEASE]")
    encrypted = bytes(b ^ 0x2F for b in confidential)

    compile_groups = [[source] for source in sources]
    by_directory = {}
    for source in sources:
        by_directory.setdefault(os.path.dirname(source), []).append(source)
    compile_groups.extend(group for group in by_directory.values() if len(group) > 1)

    errors = []
    with tempfile.TemporaryDirectory(prefix="cpp_verifier_") as temp:
        for index, group in enumerate(compile_groups):
            binary = os.path.join(temp, f"candidate_{index}")
            result = subprocess.run(
                ["g++", "-std=c++17", "-O2", *group, "-o", binary],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, check=False,
            )
            if result.returncode != 0:
                errors.append(result.stderr.decode("utf-8", "replace")[-500:])
                continue
            assert pathlib.Path(binary).read_bytes()[:4] == b"\x7fELF", "Compiled C++ artifact is not an ELF executable."
            work = os.path.join(temp, f"run_{index}")
            os.makedirs(work)
            if exercise_binary(binary, work, encrypted, confidential, public):
                return

    detail = errors[0] if errors else "compiled candidates did not decrypt the randomized input"
    assert False, "No submitted C++ program could be compiled and executed to XOR-decrypt an unseen .xrd input. " + detail
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
