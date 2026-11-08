#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import gzip
import io
import os
import re
import secrets
import subprocess
import tarfile
import zipfile

import pytest

PROJECT = "/home/user/docs_project"
ZIP_PATH = os.path.join(PROJECT, "modern_manuals.zip")
TAR_PATH = os.path.join(PROJECT, "old_manuals.tar")
C_PATH = os.path.join(PROJECT, "transformer.c")
SCRIPT_PATH = os.path.join(PROJECT, "process.sh")

TOKEN = secrets.token_hex(8)
EXTRA_TXT = f"audit_{TOKEN}.txt.gz"
EXTRA_MD = f"audit_{TOKEN}.md.gz"
EXTRA_TEXT = (
    f"<<TITLE>>Prueba dinámica {TOKEN}<</TITLE>>\n"
    "Información en español: año, café y pingüino.\n"
    f"Otro encabezado: <<TITLE>>Sección {TOKEN}<</TITLE>>\n"
)
EXPECTED_EXTRA = (
    f"# Prueba dinámica {TOKEN}\n"
    "Información en español: año, café y pingüino.\n"
    f"Otro encabezado: # Sección {TOKEN}\n"
)


def transform_expected(raw):
    return raw.decode("iso-8859-1").replace("<<TITLE>>", "# ").replace("<</TITLE>>", "")


def strip_c_comments(source):
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    return re.sub(r"//[^\n]*", "", source)


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    assert os.path.isfile(C_PATH), f"Error: {C_PATH} not found"
    assert os.path.isfile(SCRIPT_PATH), f"Error: {SCRIPT_PATH} not found"
    assert os.path.isfile(TAR_PATH), f"Error: {TAR_PATH} not found"

    with tarfile.open(TAR_PATH, "r:") as old_tar:
        original = []
        for member in old_tar.getmembers():
            if member.isfile():
                extracted = old_tar.extractfile(member)
                assert extracted is not None
                original.append((member.name, extracted.read(), member.mode))

    with tarfile.open(TAR_PATH, "w:") as new_tar:
        for name, data, mode in original:
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = mode
            new_tar.addfile(info, io.BytesIO(data))

        extra_data = gzip.compress(EXTRA_TEXT.encode("iso-8859-1"))
        info = tarfile.TarInfo(EXTRA_TXT)
        info.size = len(extra_data)
        info.mode = 0o644
        new_tar.addfile(info, io.BytesIO(extra_data))

    for name in os.listdir(PROJECT):
        path = os.path.join(PROJECT, name)
        if os.path.isfile(path) and (name.endswith(".txt.gz") or name.endswith(".md.gz") or name == "modern_manuals.zip"):
            os.remove(path)

    result = subprocess.run(
        ["bash", SCRIPT_PATH],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, f"process.sh failed:\n{result.stdout}"


def test_required_artifacts_and_zlib_program(tmp_path):
    assert os.path.isfile(C_PATH), f"Error: {C_PATH} not found"
    assert os.path.isfile(SCRIPT_PATH), f"Error: {SCRIPT_PATH} not found"

    with open(C_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = strip_c_comments(f.read())
    assert re.search(r"#\s*include\s*[<\"]zlib\.h[>\"]", source), "transformer.c must include zlib.h"
    assert re.search(r"\bgzopen\s*\(", source), "transformer.c must use gzopen"
    assert re.search(r"\b(?:gzread|gzgets|gzfread)\s*\(", source), "transformer.c must read through zlib"
    assert re.search(r"\b(?:gzwrite|gzputs|gzfwrite)\s*\(", source), "transformer.c must write through zlib"

    with open(SCRIPT_PATH, "r", encoding="utf-8", errors="replace") as f:
        script = f.read()
    assert "transformer.c" in script, "process.sh must compile transformer.c"
    assert re.search(r"\b(?:gcc|cc|clang|make)\b", script), "process.sh must contain a compilation step"

    binary = tmp_path / "transformer"
    build = subprocess.run(
        ["gcc", C_PATH, "-o", str(binary), "-lz"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert build.returncode == 0, f"transformer.c does not compile with zlib:\n{build.stdout}"

    probe_text = (
        f"<<TITLE>>Compilación {TOKEN}<</TITLE>>\n"
        "Línea con caracteres ISO-8859-1: acción, niño, über.\n"
        f"<<TITLE>>Final {TOKEN}<</TITLE>>\n"
    )
    probe_in = tmp_path / "probe.txt.gz"
    probe_out = tmp_path / "probe.md.gz"
    probe_in.write_bytes(gzip.compress(probe_text.encode("iso-8859-1")))

    run = subprocess.run(
        [str(binary), str(probe_in), str(probe_out)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert run.returncode == 0, f"compiled transformer failed:\n{run.stdout}"
    assert probe_out.is_file(), "compiled transformer did not create its output"
    converted = gzip.decompress(probe_out.read_bytes()).decode("utf-8")
    assert converted == probe_text.replace("<<TITLE>>", "# ").replace("<</TITLE>>", "")


def test_zip_file_exists():
    assert os.path.isfile(ZIP_PATH), f"Error: {ZIP_PATH} not found"


def test_zip_contents():
    assert os.path.isfile(ZIP_PATH), f"Error: {ZIP_PATH} not found"

    with zipfile.ZipFile(ZIP_PATH, 'r') as z:
        namelist = z.namelist()

        # Check if the expected files are in the zip
        assert "chapter1.md.gz" in namelist or any(n.endswith("chapter1.md.gz") for n in namelist), "Error: chapter1.md.gz not found in zip"
        assert "chapter2.md.gz" in namelist or any(n.endswith("chapter2.md.gz") for n in namelist), "Error: chapter2.md.gz not found in zip"

        expected = {"chapter1.md.gz", "chapter2.md.gz", EXTRA_MD}
        assert len(namelist) == len(expected), "Zip must contain only generated .md.gz files"
        assert all(not n.endswith("/") and n.endswith(".md.gz") for n in namelist), "Zip contains a non-.md.gz entry"
        assert {os.path.basename(n) for n in namelist} == expected, "Zip contents do not match all tar inputs"


def test_chapter1_content():
    assert os.path.isfile(ZIP_PATH), f"Error: {ZIP_PATH} not found"

    with zipfile.ZipFile(ZIP_PATH, 'r') as z:
        chap1_name = next((n for n in z.namelist() if n.endswith("chapter1.md.gz")), None)
        assert chap1_name is not None, "Error: chapter1.md.gz not found in zip"

        with z.open(chap1_name) as f:
            with gzip.open(f, 'rt', encoding='utf-8') as gz:
                content = gz.read()

        assert "# Introducción" in content, "Error: chapter1.md content mismatch or bad encoding"
        assert "Este es el capítulo uno." in content, "Error: chapter1.md content mismatch"
        assert "TITLE" not in content, "Error: Legacy tags were not completely removed"


def test_chapter2_content():
    assert os.path.isfile(ZIP_PATH), f"Error: {ZIP_PATH} not found"

    with zipfile.ZipFile(ZIP_PATH, 'r') as z:
        chap2_name = next((n for n in z.namelist() if n.endswith("chapter2.md.gz")), None)
        assert chap2_name is not None, "Error: chapter2.md.gz not found in zip"

        with z.open(chap2_name) as f:
            with gzip.open(f, 'rt', encoding='utf-8') as gz:
                content = gz.read()

        assert "# Conclusión" in content, "Error: chapter2.md content mismatch or bad encoding"
        assert "La documentación está completa." in content, "Error: chapter2.md content mismatch"
        assert "TITLE" not in content, "Error: Legacy tags were not completely removed"


def test_randomized_archive_entry_is_fully_transformed():
    with zipfile.ZipFile(ZIP_PATH, "r") as z:
        name = next((n for n in z.namelist() if os.path.basename(n) == EXTRA_MD), None)
        assert name is not None, "process.sh did not process a newly added tar entry"
        compressed = z.read(name)

    content = gzip.decompress(compressed).decode("utf-8")
    assert content == EXPECTED_EXTRA
    assert "TITLE" not in content
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
