#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import py_compile
import shutil
import stat
import subprocess
import sys
import tarfile
import uuid
import zipfile
from pathlib import Path, PurePosixPath


def test_extracted_files_renamed_and_edited():
    extracted_dir = "/home/user/extracted_docs/legacy_docs"

    file1 = os.path.join(extracted_dir, "intro_guide.md")
    assert os.path.exists(file1), f"Expected file missing: {file1}"
    with open(file1, "r") as f:
        content = f.read()
        assert "Welcome to **[Deprecated Version]**." in content, f"Macro replacement failed in {file1}"

    file2 = os.path.join(extracted_dir, "api", "rest_spec.md")
    assert os.path.exists(file2), f"Expected file missing: {file2}"
    with open(file2, "r") as f:
        content = f.read()
        assert "API details for **[Deprecated Version]** here." in content, f"Macro replacement failed in {file2}"

    file3 = os.path.join(extracted_dir, "guides", "setup.md")
    assert os.path.exists(file3), f"Expected file missing: {file3}"
    with open(file3, "r") as f:
        content = f.read()
        assert "No macros here." in content, f"Unexpected content in {file3}"


def test_symlinks_deleted():
    extracted_dir = "/home/user/extracted_docs/legacy_docs"

    symlink1 = os.path.join(extracted_dir, "infinite_loop")
    assert not os.path.exists(symlink1) and not os.path.islink(symlink1), f"Symlink {symlink1} was not deleted"

    symlink2 = os.path.join(extracted_dir, "api", "recursive_guides")
    assert not os.path.exists(symlink2) and not os.path.islink(symlink2), f"Symlink {symlink2} was not deleted"


def test_clean_docs_zip():
    zip_path = "/home/user/clean_docs.zip"
    assert os.path.exists(zip_path), f"Zip file missing: {zip_path}"
    assert zipfile.is_zipfile(zip_path), f"File {zip_path} is not a valid zip archive"

    with zipfile.ZipFile(zip_path, 'r') as z:
        names = z.namelist()
        basenames = [os.path.basename(n) for n in names if not n.endswith('/')]

        assert "intro_guide.md" in basenames, "intro_guide.md missing from zip archive"
        assert "rest_spec.md" in basenames, "rest_spec.md missing from zip archive"
        assert "setup.md" in basenames, "setup.md missing from zip archive"

        assert "infinite_loop" not in basenames, "Symlink 'infinite_loop' should not be in zip archive"
        assert "recursive_guides" not in basenames, "Symlink 'recursive_guides' should not be in zip archive"


def test_cleanup_report():
    report_path = "/home/user/cleanup_report.txt"
    assert os.path.exists(report_path), f"Report file missing: {report_path}"

    with open(report_path, "r") as f:
        content = f.read().strip()
        assert content == "3", f"Expected report to contain exactly '3', got '{content}'"


def test_script_executes_general_cleanup(tmp_path):
    script = Path("/home/user/process_docs.py")
    assert script.exists(), "Required script /home/user/process_docs.py is missing"
    assert script.is_file() and not script.is_symlink(), "process_docs.py must be a regular file"
    py_compile.compile(str(script), doraise=True)

    token = uuid.uuid4().hex[:10]
    source_root = tmp_path / "legacy_docs"
    (source_root / "chapter").mkdir(parents=True)
    (source_root / "reference").mkdir()

    original_docs = {
        Path(f"Release {token.upper()} Notes.DOC"): f"Header {token}: <macro: old_version> and <macro: old_version>.\n",
        Path("chapter") / f"Deep Dive {token}.DOC": f"Body {token} has <macro: old_version>.\n",
        Path("chapter") / f"No Macro {token}.DOC": f"Plain text {token}.\n",
        Path("reference") / f"API  Index {token}.DOC": f"<macro: old_version> reference {token}.\n",
    }
    extra_files = {
        Path("reference") / f"keep_{token}.txt": f"Unchanged supporting file {token}.\n"
    }

    for relative, content in {**original_docs, **extra_files}.items():
        target = source_root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")

    loop_name = f"loop_{token}"
    nested_link_name = f"chapter_link_{token}"
    broken_link_name = f"broken_{token}"
    os.symlink(".", source_root / loop_name)
    os.symlink("../chapter", source_root / "reference" / nested_link_name)
    os.symlink("missing-target", source_root / broken_link_name)

    archive = Path("/home/user/legacy_docs.tar.gz")
    extracted = Path("/home/user/extracted_docs")
    zip_path = Path("/home/user/clean_docs.zip")
    report = Path("/home/user/cleanup_report.txt")

    shutil.rmtree(extracted, ignore_errors=True)
    for output in (zip_path, report):
        if output.exists() or output.is_symlink():
            output.unlink()

    with tarfile.open(archive, "w:gz", dereference=False) as tf:
        tf.add(source_root, arcname="legacy_docs", recursive=True)

    result = subprocess.run(
        [sys.executable, str(script)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process_docs.py failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    output_root = extracted / "legacy_docs"
    assert output_root.is_dir(), "Script did not extract the generated archive"

    expected_files = {}
    for relative, content in original_docs.items():
        new_name = relative.name[:-4].lower().replace(" ", "_") + ".md"
        renamed = relative.with_name(new_name)
        expected_files[renamed] = content.replace(
            "<macro: old_version>", "**[Deprecated Version]**"
        )
    expected_files.update(extra_files)

    for relative, expected_content in expected_files.items():
        path = output_root / relative
        assert path.is_file() and not path.is_symlink(), f"Expected processed file missing: {path}"
        assert path.read_text(encoding="utf-8") == expected_content, f"Incorrect content in {path}"

    for old_relative in original_docs:
        assert not (output_root / old_relative).exists(), f"Old .DOC file remains: {old_relative}"

    found_symlinks = []
    for current, dirs, files in os.walk(output_root, followlinks=False):
        for name in dirs + files:
            candidate = Path(current) / name
            if candidate.is_symlink():
                found_symlinks.append(str(candidate))
    assert not found_symlinks, f"Extracted tree still contains symlinks: {found_symlinks}"

    assert zip_path.exists() and zipfile.is_zipfile(zip_path), "Script did not create a valid ZIP"
    symlink_names = {loop_name, nested_link_name, broken_link_name}
    with zipfile.ZipFile(zip_path, "r") as zf:
        infos = zf.infolist()
        file_infos = [info for info in infos if not info.is_dir()]
        assert not any(stat.S_ISLNK((info.external_attr >> 16) & 0xFFFF) for info in infos), \
            "ZIP archive contains a symlink"
        assert not any(PurePosixPath(info.filename).name in symlink_names for info in infos), \
            "Deleted symlink was included in ZIP archive"
        assert not any(info.filename.endswith(".DOC") for info in file_infos), \
            "ZIP archive contains an unrenamed .DOC file"

        for relative, expected_content in expected_files.items():
            suffix = "legacy_docs/" + relative.as_posix()
            matches = [
                info for info in file_infos
                if info.filename.lstrip("./") == suffix
                or info.filename.lstrip("./").endswith("/" + suffix)
            ]
            assert len(matches) == 1, f"Expected exactly one ZIP member for {relative}, found {len(matches)}"
            actual = zf.read(matches[0]).decode("utf-8")
            assert actual == expected_content, f"Incorrect archived content for {relative}"

    assert report.exists(), "Cleanup report was not generated"
    assert report.read_text(encoding="utf-8").strip() == str(len(original_docs)), \
        "Cleanup report does not contain the dynamically processed .md count"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
