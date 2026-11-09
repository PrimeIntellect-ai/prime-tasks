#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess
import tarfile
import uuid
from pathlib import Path


def test_doc_parser_c_exists():
    c_file_path = "/home/user/doc_parser.c"
    assert os.path.isfile(c_file_path), f"The required C program was not found at {c_file_path}"


def test_final_docs_archive_exists():
    archive_path = "/home/user/final_docs.tar.gz"
    assert os.path.isfile(archive_path), f"The final archive was not found at {archive_path}"


def test_final_docs_archive_contents():
    archive_path = "/home/user/final_docs.tar.gz"
    assert os.path.isfile(archive_path), "Archive missing, cannot check contents"

    expected_files = {
        "installation_guide.txt": b"setup content\n",
        "authentication_v2.txt": b"new api content\n",
        "for_loops_tutorial.txt": b"loop content\n"
    }

    actual_files = {}

    with tarfile.open(archive_path, "r:gz") as tar:
        for member in tar.getmembers():
            assert not member.isdir(), f"Archive should not contain directories, found: {member.name}"
            assert "/" not in member.name and "\\" not in member.name, f"Archive should only contain flattened files, found nested path: {member.name}"

            f = tar.extractfile(member)
            if f is not None:
                actual_files[member.name] = f.read()

    assert set(actual_files.keys()) == set(expected_files.keys()), (
        f"Archive contents do not match expected. "
        f"Expected: {list(expected_files.keys())}, Found: {list(actual_files.keys())}"
    )

    for filename, expected_content in expected_files.items():
        assert actual_files[filename].strip() == expected_content.strip(), (
            f"Content mismatch in {filename}. "
            f"Expected: {expected_content}, Found: {actual_files[filename]}"
        )


def test_c_program_processes_csv_on_fresh_fixture():
    source = Path("/home/user/doc_parser.c")
    executable = Path("/tmp/doc_parser_verifier")
    compile_result = subprocess.run(
        ["gcc", str(source), "-o", str(executable)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"doc_parser.c did not compile:\n{compile_result.stderr}"

    token = uuid.uuid4().hex[:10]
    root = Path("/home/user/legacy_docs")
    csv_path = Path("/home/user/doc_index.csv")
    output = Path("/home/user/approved_docs")
    input_archive = Path("/home/user/legacy_docs.tar.gz")

    approved = {
        f"source_alpha_{token}.txt": (f"renamed_alpha_{token}.txt", b"dynamic alpha content\n", "deep/alpha"),
        f"source_beta_{token}.txt": (f"renamed_beta_{token}.txt", b"dynamic beta content\n", "other/beta/nested"),
    }
    ignored = {
        f"draft_{token}.txt": (f"draft_new_{token}", b"dynamic draft content\n", "ignored/drafts", "draft"),
        f"case_{token}.txt": (f"case_new_{token}", b"dynamic case content\n", "ignored/case", "Approved"),
        f"space_{token}.txt": (f"space_new_{token}", b"dynamic space content\n", "ignored/space", "approved "),
    }
    unlisted_name = f"unlisted_{token}.txt"
    unlisted_content = b"dynamic unlisted content\n"

    def prepare_fixture():
        shutil.rmtree(root, ignore_errors=True)
        shutil.rmtree(output, ignore_errors=True)
        if input_archive.exists():
            input_archive.unlink()
        root.mkdir(parents=True)

        for original, (_, content, folder) in approved.items():
            path = root / folder / original
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)

        for original, (_, content, folder, _) in ignored.items():
            path = root / folder / original
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)

        unlisted = root / "misc" / unlisted_name
        unlisted.parent.mkdir(parents=True, exist_ok=True)
        unlisted.write_bytes(unlisted_content)

        lines = ["original_filename,new_filename,section,status"]
        for original, (renamed, _, _) in approved.items():
            lines.append(f"{original},{Path(renamed).stem},dynamic,approved")
        for original, (renamed, _, _, status) in ignored.items():
            lines.append(f"{original},{renamed},dynamic,{status}")
        csv_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

        with tarfile.open(input_archive, "w:gz") as tar:
            tar.add(root, arcname="legacy_docs")

    def result_is_correct():
        if not output.is_dir():
            return False
        files = {p.name: p.read_bytes() for p in output.iterdir() if p.is_file()}
        expected = {renamed: content for _, (renamed, content, _) in approved.items()}
        if files != expected:
            return False
        for original, (_, _, folder) in approved.items():
            if (root / folder / original).exists():
                return False
        for original, (_, content, folder, _) in ignored.items():
            path = root / folder / original
            if not path.is_file() or path.read_bytes() != content:
                return False
        unlisted = root / "misc" / unlisted_name
        return unlisted.is_file() and unlisted.read_bytes() == unlisted_content

    invocations = [
        [],
        [str(csv_path)],
        [str(csv_path), str(root)],
        [str(csv_path), str(root), str(output)],
        [str(root), str(csv_path), str(output)],
    ]

    outcomes = []
    for args in invocations:
        prepare_fixture()
        try:
            proc = subprocess.run(
                [str(executable), *args],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=15,
            )
            outcomes.append((args, proc.returncode, proc.stderr[-500:]))
        except subprocess.TimeoutExpired:
            outcomes.append((args, "timeout", ""))
            continue
        if result_is_correct():
            return

    raise AssertionError(
        "The compiled C program did not parse and process a fresh CSV fixture correctly. "
        f"Invocation outcomes: {outcomes}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
