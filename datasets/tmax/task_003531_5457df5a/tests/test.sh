#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import subprocess
import tarfile

FINAL = "/home/user/final_docs.tar.gz"
ORGANIZED = "/home/user/organized_docs"
EXTRACTED = "/home/user/extracted_docs"
SHDOC = "/home/user/.local/bin/shdoc"

MAPPING = "intro.md:basics/introduction.md\ndeploy_script.sh:scripts/deploy.sh\n"
INTRO_OLD = "This is an intro.\nCheck out the [[Setup Guide]] and [[Wiki Links]].\nAlso [Markdown](links.md).\n"
INTRO_NEW = "This is an intro.\nCheck out the [Setup Guide](Setup_Guide.md) and [Wiki Links](Wiki_Links.md).\nAlso [Markdown](links.md).\n"
DEPLOY = '#!/bin/bash\n# @name deploy\n# @description Deploys the app\necho "Deploying"\n'
API = "# API Documentation\n\nname deploy\ndescription Deploys the app\n"


def read_file(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def logical_tar_name(name):
    parts = [p for p in name.lstrip("/").split("/") if p not in ("", ".")]
    if "organized_docs" in parts:
        parts = parts[parts.index("organized_docs") + 1:]
    return "/".join(parts)


def archive_files(path):
    result = {}
    with tarfile.open(path, "r:gz") as tar:
        for member in tar.getmembers():
            logical = logical_tar_name(member.name)
            if member.isdir() or not logical:
                continue
            assert member.isfile(), f"Unexpected non-regular archive entry: {member.name}"
            assert logical not in result, f"Duplicate archive path: {logical}"
            stream = tar.extractfile(member)
            assert stream is not None
            result[logical] = stream.read().decode("utf-8", errors="strict")
    return result


def test_final_docs_tarball_exists():
    path = FINAL
    assert os.path.exists(path), f"Final docs tarball {path} does not exist. Did you create the final archive?"
    assert os.path.isfile(path), f"{path} is not a file."


def test_link_conversion_accuracy_and_api_doc():
    path = FINAL
    assert os.path.exists(path), f"Final docs tarball {path} does not exist."

    correct_conversions = 0
    leftover_wiki_links = 0
    has_api_doc = False

    try:
        with tarfile.open(path, 'r:gz') as tar:
            for member in tar.getmembers():
                if member.name.endswith('deploy_api.md'):
                    has_api_doc = True

                if member.name.endswith('.md') and member.isfile():
                    f = tar.extractfile(member)
                    if f is not None:
                        content = f.read().decode('utf-8', errors='replace')
                        leftovers = len(re.findall(r'\[\[.*?\]\]', content))
                        leftover_wiki_links += leftovers
                        corrects = len(re.findall(r'\[(.*?)\]\(\1\.md\)', content.replace(' ', '_')))
                        correct_conversions += corrects
    except Exception as e:
        assert False, f"Failed to read or parse the tarball {path}: {e}"

    assert has_api_doc, "deploy_api.md is missing from the final archive. Did you generate the documentation using shdoc?"

    total = correct_conversions + leftover_wiki_links
    if total == 0:
        accuracy = 1.0
    else:
        accuracy = correct_conversions / total

    assert accuracy >= 0.95, f"Link conversion accuracy {accuracy:.2f} is below threshold 0.95. Correct: {correct_conversions}, Leftover: {leftover_wiki_links}."


def test_legacy_archive_checksum_and_contents():
    archive = "/home/user/legacy_docs.tar.gz"
    checksum = "/home/user/legacy_docs.md5"
    assert os.path.isfile(archive)
    assert os.path.isfile(checksum)
    proc = subprocess.run(
        ["md5sum", "-c", checksum], cwd="/home/user",
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10
    )
    assert proc.returncode == 0, f"Legacy archive checksum does not verify:\n{proc.stdout}"

    expected = {
        "mapping.conf": MAPPING,
        "intro.md": INTRO_OLD,
        "deploy_script.sh": DEPLOY,
    }
    actual = {}
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar.getmembers():
            if member.isdir():
                continue
            assert member.isfile(), f"Unexpected legacy archive entry: {member.name}"
            name = member.name.lstrip("./")
            stream = tar.extractfile(member)
            assert stream is not None
            actual[name] = stream.read().decode("utf-8", errors="strict")
    assert actual == expected, "The supplied legacy archive no longer has the expected contents"


def test_extraction_and_organized_directory_state():
    assert os.path.isdir(EXTRACTED), "extracted_docs was not created"
    assert read_file(os.path.join(EXTRACTED, "mapping.conf")) == MAPPING
    assert not os.path.exists(os.path.join(EXTRACTED, "intro.md")), "Mapped intro.md was not moved"
    assert not os.path.exists(os.path.join(EXTRACTED, "deploy_script.sh")), "Mapped deploy_script.sh was not moved"

    expected = {
        "basics/introduction.md": INTRO_NEW,
        "scripts/deploy.sh": DEPLOY,
        "scripts/deploy_api.md": API,
    }
    actual = {}
    for root, dirs, files in os.walk(ORGANIZED):
        for name in files:
            path = os.path.join(root, name)
            rel = os.path.relpath(path, ORGANIZED).replace(os.sep, "/")
            assert not os.path.islink(path), f"Organized file must not be a symlink: {rel}"
            actual[rel] = read_file(path)
    assert actual == expected, "organized_docs does not contain the correctly mapped and transformed files"


def test_fixed_shdoc_is_installed_and_functional():
    assert os.path.isfile(SHDOC), "shdoc was not installed to ~/.local/bin/shdoc"
    assert os.access(SHDOC, os.X_OK), "Installed shdoc is not executable"
    source = read_file(SHDOC)
    assert "/opt/bin/gawk" not in source, "Installed shdoc still contains the broken AWK path"

    env = os.environ.copy()
    env["HOME"] = "/home/user"
    found = subprocess.run(
        ["bash", "-c", "source ~/.profile >/dev/null 2>&1 || true; command -v shdoc"],
        cwd="/home/user", env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert found.returncode == 0 and os.path.realpath(found.stdout.strip()) == SHDOC, "shdoc is not available in the user's PATH"

    generated = subprocess.run(
        [SHDOC, os.path.join(ORGANIZED, "scripts/deploy.sh")],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert generated.returncode == 0, f"Installed shdoc failed: {generated.stderr}"
    assert generated.stdout == API, "Installed shdoc did not generate the expected API documentation"
    assert read_file(os.path.join(ORGANIZED, "scripts/deploy_api.md")) == generated.stdout


def test_final_archive_has_exact_organized_results():
    expected = {
        "basics/introduction.md": INTRO_NEW,
        "scripts/deploy.sh": DEPLOY,
        "scripts/deploy_api.md": API,
    }
    assert archive_files(FINAL) == expected, "Final archive does not contain the complete organized documentation tree"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
