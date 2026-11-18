#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import stat
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path

import pytest
from PIL import Image, ImageDraw, ImageFont

TAR_PATH = "/home/user/final_archive.tar.xz"
CURATED_DIR = "/home/user/curated_artifacts"
REGISTRY_PATH = "/home/user/registry.json"
INCOMING_DIR = "/home/user/incoming_artifacts"
RULE_IMAGE = "/app/curation_rules.png"
EXPECTED_CONTENTS = {}


def _find_workflow_script():
    candidates = []
    roots = [Path("/home/user"), Path("/app"), Path("/tmp")]
    excluded_parts = {"incoming_artifacts", "curated_artifacts", "__pycache__"}

    for root in roots:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            try:
                if not path.is_file() or path.is_symlink():
                    continue
                if any(part in excluded_parts for part in path.parts):
                    continue
                if str(path).startswith("/tmp/test_"):
                    continue
                if path.stat().st_size > 1024 * 1024:
                    continue
                mode = path.stat().st_mode
                if path.suffix.lower() not in {".py", ".sh", ".rb", ".pl"} and not (mode & stat.S_IXUSR):
                    continue
                text = path.read_text(errors="ignore")
            except (OSError, UnicodeError):
                continue

            workflow_terms = sum(term in text for term in (
                "incoming_artifacts", "curated_artifacts", "registry.json",
                "curation_rules", "final_archive"
            ))
            if workflow_terms < 3:
                continue

            has_ocr = re.search(r"\b(?:pytesseract|tesseract|easyocr)\b", text, re.I)
            has_concurrency = re.search(
                r"ThreadPoolExecutor\s*\(|ProcessPoolExecutor\s*\(|"
                r"multiprocessing\.(?:Pool|Process)\s*\(|\bPool\s*\(|"
                r"threading\.Thread\s*\(|asyncio\.(?:gather|create_task)\s*\(|"
                r"\bxargs\b[^\n]*\s-P\s*\d+|\bparallel\b|&\s*(?:#.*)?$",
                text, re.I | re.M
            )
            has_lock = re.search(
                r"fcntl\s*\.\s*flock\s*\(|(?:from\s+fcntl\s+import[^\n]*\bflock\b[\s\S]*?\bflock\s*\()|"
                r"\.flock\s*\(|\bflock\s+|\bportalocker\b|\bfilelock\b|\blockf\s*\(",
                text, re.I
            )
            if has_ocr and has_concurrency and has_lock:
                candidates.append((workflow_terms, path))

    assert candidates, (
        "No runnable workflow script was found that reads the OCR rules, processes "
        "archives concurrently, and uses file locking for the registry"
    )
    candidates.sort(key=lambda item: (-item[0], len(str(item[1]))))
    return candidates[0][1]


def _command_for(path):
    suffix = path.suffix.lower()
    if suffix == ".py":
        return [sys.executable, str(path)]
    if suffix == ".sh":
        return ["bash", str(path)]
    if suffix == ".rb":
        return ["ruby", str(path)]
    if suffix == ".pl":
        return ["perl", str(path)]
    return [str(path)]


def test_00_execute_workflow_script_on_fresh_inputs():
    global EXPECTED_CONTENTS
    script = _find_workflow_script()

    font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    font = ImageFont.truetype(font_path, 46) if os.path.exists(font_path) else ImageFont.load_default()
    image = Image.new("RGB", (900, 150), "white")
    draw = ImageDraw.Draw(image)
    draw.text((20, 35), "BANNED_EXTENSION=.ban", fill="black", font=font)
    image.save(RULE_IMAGE)

    secrets = {
        "safe_bin1.exe": os.urandom(48),
        "safe_bin2.exe": os.urandom(48),
        "safe_bin3.exe": os.urandom(48),
    }
    EXPECTED_CONTENTS = secrets

    os.makedirs(INCOMING_DIR, exist_ok=True)
    for name in os.listdir(INCOMING_DIR):
        path = os.path.join(INCOMING_DIR, name)
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)

    with zipfile.ZipFile(os.path.join(INCOMING_DIR, "archive1.zip"), "w") as zf:
        zf.writestr("safe_bin1.exe", secrets["safe_bin1.exe"])
        zf.writestr("library.ban", b"must be filtered based on OCR")
    with zipfile.ZipFile(os.path.join(INCOMING_DIR, "archive2.zip"), "w") as zf:
        zf.writestr("safe_bin2.exe", secrets["safe_bin2.exe"])
        zf.writestr("../../../../home/user/pwned.txt", b"pwned")
    with zipfile.ZipFile(os.path.join(INCOMING_DIR, "archive3.zip"), "w") as zf:
        zf.writestr("safe_bin3.exe", secrets["safe_bin3.exe"])

    if os.path.isdir(CURATED_DIR):
        import shutil
        shutil.rmtree(CURATED_DIR)
    elif os.path.lexists(CURATED_DIR):
        os.unlink(CURATED_DIR)
    if os.path.lexists(REGISTRY_PATH):
        os.unlink(REGISTRY_PATH)
    for escaped in ("/home/user/pwned.txt", "/pwned.txt"):
        if os.path.lexists(escaped):
            os.unlink(escaped)

    result = subprocess.run(
        _command_for(script), cwd=str(script.parent), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60
    )
    assert result.returncode == 0, f"Workflow script failed:\n{result.stdout}"

    for relative, expected in secrets.items():
        output = os.path.join(CURATED_DIR, relative)
        assert os.path.isfile(output), f"Workflow did not extract {relative}"
        with open(output, "rb") as f:
            assert f.read() == expected, f"Extracted data for {relative} does not match its ZIP member"

    assert not os.path.exists(os.path.join(CURATED_DIR, "library.ban")), (
        "The extension read from the updated OCR rule image was not filtered"
    )
    assert not os.path.exists("/home/user/pwned.txt")
    assert not os.path.exists("/pwned.txt")


def test_final_archive_exists():
    assert os.path.exists(TAR_PATH), f"Final archive missing at {TAR_PATH}"
    assert os.path.isfile(TAR_PATH), f"Path {TAR_PATH} is not a file"


def test_zip_slip_prevented():
    assert not os.path.exists("/home/user/pwned.txt"), "Zip slip payload was extracted to /home/user/pwned.txt!"
    assert not os.path.exists("/pwned.txt"), "Zip slip payload was extracted to /pwned.txt!"


def test_final_archive_size():
    assert os.path.exists(TAR_PATH), f"Final archive missing at {TAR_PATH}"
    size = os.path.getsize(TAR_PATH)
    threshold = 1500
    assert size <= threshold, f"Archive size {size} bytes exceeds maximum threshold of {threshold} bytes. Extreme compression (e.g., xz -9) is required."


def test_curated_artifacts_contents():
    assert os.path.exists(CURATED_DIR), f"Curated directory missing at {CURATED_DIR}"
    assert os.path.isdir(CURATED_DIR), f"Path {CURATED_DIR} is not a directory"

    files_in_curated = set()
    for root, _, files in os.walk(CURATED_DIR):
        for file in files:
            files_in_curated.add(file)
            assert not file.endswith(".dll"), f"Banned file {file} was extracted into curated directory."
            assert not file.endswith(".ban"), f"OCR-derived banned file {file} was extracted into curated directory."
            assert file != "pwned.txt", "Zip slip payload found in curated directory."

    expected_files = {"safe_bin1.exe", "safe_bin2.exe", "safe_bin3.exe"}
    assert files_in_curated == expected_files, f"Curated directory contents mismatch. Expected {expected_files}, got {files_in_curated}"


def test_registry_json_contents():
    assert os.path.exists(REGISTRY_PATH), f"Registry missing at {REGISTRY_PATH}"
    with open(REGISTRY_PATH, "r") as f:
        try:
            registry = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("registry.json is not valid JSON")

    assert isinstance(registry, list), "Registry should be a JSON array"

    expected_files = {"safe_bin1.exe", "safe_bin2.exe", "safe_bin3.exe"}
    actual_files = set(os.path.basename(p) for p in registry)
    assert actual_files == expected_files, f"Registry contents mismatch. Expected {expected_files}, got {actual_files}"
    assert len(registry) == 3, "Registry must contain exactly one entry per extracted file"

    for p in registry:
        assert isinstance(p, str), "Registry entries must be paths"
        assert not os.path.isabs(p), f"Registry path must be relative: {p}"
        assert ".." not in Path(p).parts, f"Unsafe registry path: {p}"
        assert not p.endswith(".dll"), f"Banned file extension found in registry: {p}"
        assert not p.endswith(".ban"), f"OCR-derived banned extension found in registry: {p}"
        assert "pwned.txt" not in p, f"Zip slip payload found in registry: {p}"


def test_tarball_contents():
    assert os.path.exists(TAR_PATH), f"Final archive missing at {TAR_PATH}"
    try:
        with tarfile.open(TAR_PATH, "r:xz") as tar:
            names = tar.getnames()
    except tarfile.ReadError:
        pytest.fail(f"{TAR_PATH} is not a valid xz-compressed tar file")

    basenames = set(os.path.basename(name) for name in names if os.path.basename(name))
    expected_basenames = {"safe_bin1.exe", "safe_bin2.exe", "safe_bin3.exe", "registry.json"}

    for expected in expected_basenames:
        assert expected in basenames, f"Expected file {expected} missing from tarball"

    for name in basenames:
        assert not name.endswith(".dll"), f"Banned file extension found in tarball: {name}"
        assert not name.endswith(".ban"), f"OCR-derived banned extension found in tarball: {name}"
        assert name != "pwned.txt", "Zip slip payload found in tarball"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
