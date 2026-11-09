#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import io
import os
import secrets
import subprocess
import tarfile
import zipfile

SCRIPT_PATH = "/home/user/parse_docs.py"
ARCHIVE_PATH = "/home/user/docs_archive.tar"
OUTPUT_PATH = "/home/user/compiled_docs.md"

EXPECTED_ORIGINAL = (
    "### FILE: alpha.md\n"
    "# Alpha\n"
    "This is the alpha doc.\n\n"
    "### FILE: beta.md\n"
    "# Beta\n"
    "Beta documentation.\n\n"
    "### FILE: delta.md\n"
    "# Delta\n"
    "Delta notes.\n\n"
    "### FILE: gamma.md\n"
    "# Gamma\n"
    "Gamma notes.\n\n"
)


def run_script():
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"parse_docs.py exited with status {result.returncode}.\n"
        f"stderr:\n{result.stderr}"
    )
    return result.stdout


def make_tar_bytes(files):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w") as archive:
        for name, data in files.items():
            encoded = data if isinstance(data, bytes) else data.encode("utf-8")
            info = tarfile.TarInfo(name=name)
            info.size = len(encoded)
            archive.addfile(info, io.BytesIO(encoded))
    return output.getvalue()


def format_docs(docs):
    return "".join(
        f"### FILE: {basename}\n{content}\n\n"
        for basename, content in sorted(docs, key=lambda item: item[0])
    )


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file"


def test_compiled_docs_exists():
    assert os.path.exists(OUTPUT_PATH), f"Output file not found at {OUTPUT_PATH}"
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file"


def test_compiled_docs_content():
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        actual_content = f.read()

    assert actual_content == EXPECTED_ORIGINAL, (
        "The contents of compiled_docs.md do not match the expected output. "
        "Ensure all .md files are extracted, sorted by basename, and formatted correctly."
    )


def test_script_executes_on_original_archive():
    assert run_script() == EXPECTED_ORIGINAL, (
        "Executing parse_docs.py on docs_archive.tar did not produce the required stdout."
    )


def test_recursive_magic_number_detection_with_dynamic_input():
    token = secrets.token_hex(8)
    outer_name = f"z_outer_{token}.md"
    zip_name = f"a_zip_{token}.md"
    gzip_name_1 = f"m_gzip_{token}.md"
    gzip_name_2 = f"b_gzip_{token}.md"

    dynamic_docs = [
        ("alpha.md", "# Alpha\nThis is the alpha doc."),
        ("beta.md", "# Beta\nBeta documentation."),
        ("gamma.md", "# Gamma\nGamma notes."),
        ("delta.md", "# Delta\nDelta notes."),
        (outer_name, f"dynamic outer content {token}"),
        (zip_name, f"dynamic zip content {token}"),
        (gzip_name_1, f"dynamic gzip content one {token}"),
        (gzip_name_2, f"dynamic gzip content two {token}"),
    ]

    inner_tar = make_tar_bytes({
        "nested/gamma.md": "# Gamma\nGamma notes.",
        "other/delta.md": "# Delta\nDelta notes.",
        f"nested/{gzip_name_1}": f"dynamic gzip content one {token}",
        f"other/{gzip_name_2}": f"dynamic gzip content two {token}",
    })
    disguised_gzip = gzip.compress(inner_tar)

    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("docs/beta.md", "# Beta\nBeta documentation.")
        archive.writestr(f"docs/{zip_name}", f"dynamic zip content {token}")
        archive.writestr(f"payload_{token}.bin", disguised_gzip)
        archive.writestr("ignore.txt", "not markdown")
    disguised_zip = zip_buffer.getvalue()

    outer_tar = make_tar_bytes({
        "alpha.md": "# Alpha\nThis is the alpha doc.",
        f"docs/{outer_name}": f"dynamic outer content {token}",
        f"project_{token}.dat": disguised_zip,
        "ordinary.bin": b"not an archive",
    })

    with open(ARCHIVE_PATH, "rb") as f:
        original_archive = f.read()
    with open(OUTPUT_PATH, "rb") as f:
        original_output = f.read()

    try:
        with open(ARCHIVE_PATH, "wb") as f:
            f.write(outer_tar)

        actual = run_script()
        expected = format_docs(dynamic_docs)
        assert actual == expected, (
            "parse_docs.py failed on a dynamic recursively nested ZIP/GZIP input whose "
            "inner archives had misleading .dat and .bin extensions."
        )
    finally:
        with open(ARCHIVE_PATH, "wb") as f:
            f.write(original_archive)
        with open(OUTPUT_PATH, "wb") as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
