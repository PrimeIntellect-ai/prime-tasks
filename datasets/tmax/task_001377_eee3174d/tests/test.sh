#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import io
import os
import re
import secrets
import shutil
import subprocess
import tarfile
from pathlib import Path

import pytest

SCRIPT_PATH = "/home/user/validate_config.sh"
POLICY_PATH = "/app/policy.png"
CLEAN_DIR = "/app/corpora/clean"
EVIL_DIR = "/app/corpora/evil"


def run_script(*args, cwd=None):
    return subprocess.run(
        ["bash", SCRIPT_PATH, *map(str, args)],
        cwd=cwd,
        capture_output=True,
        timeout=15,
    )


def make_tar(path, members):
    """Create a tar whose members map archive names to bytes."""
    with tarfile.open(path, "w") as archive:
        for name, content in members:
            data = content if isinstance(content, bytes) else content.encode()
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(data))


def policy_code(path=POLICY_PATH):
    result = subprocess.run(
        ["tesseract", str(path), "stdout"],
        capture_output=True,
        text=True,
        timeout=15,
        check=True,
    )
    match = re.search(r"DEPARTMENT_CODE:\s*([A-Z0-9-]+)", result.stdout)
    assert match, f"Could not OCR department code from policy image: {result.stdout!r}"
    return match.group(1)


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_policy_fixture_unchanged():
    assert policy_code() == "OMEGA-77-XRAY", "The supplied policy image was modified"


def test_clean_corpus_accepted():
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus directory missing: {CLEAN_DIR}"
    clean_files = [f for f in os.listdir(CLEAN_DIR) if f.endswith('.tar')]
    assert len(clean_files) > 0, "No clean tarballs found to test."

    failed_files = []
    for f in clean_files:
        path = os.path.join(CLEAN_DIR, f)
        result = subprocess.run(["bash", SCRIPT_PATH, path], capture_output=True)
        if result.returncode != 0:
            failed_files.append(f)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(clean_files)} clean modified (rejected instead of accepted). Offending files: {', '.join(failed_files)}")


def test_evil_corpus_rejected():
    assert os.path.isdir(EVIL_DIR), f"Evil corpus directory missing: {EVIL_DIR}"
    evil_files = [f for f in os.listdir(EVIL_DIR) if f.endswith('.tar')]
    assert len(evil_files) > 0, "No evil tarballs found to test."

    failed_files = []
    for f in evil_files:
        path = os.path.join(EVIL_DIR, f)
        result = subprocess.run(["bash", SCRIPT_PATH, path], capture_output=True)
        if result.returncode == 0:
            failed_files.append(f)

    if failed_files:
        pytest.fail(f"{len(failed_files)} of {len(evil_files)} evil bypassed (accepted instead of rejected). Offending files: {', '.join(failed_files)}")


def test_exactly_one_absolute_tar_argument(tmp_path):
    code = policy_code()
    valid = tmp_path / "argument-check.tar"
    make_tar(valid, [("settings.conf", f"DEPT={code}\n"), ("data.txt", "safe\n")])

    assert run_script().returncode == 1, "No arguments must be rejected with status 1"
    assert run_script(valid, valid).returncode == 1, "Multiple arguments must be rejected with status 1"
    assert run_script(valid.name, cwd=tmp_path).returncode == 1, "A relative archive path must be rejected"

    malformed = tmp_path / "malformed.tar"
    malformed.write_text("this is not a tar archive")
    assert run_script(malformed).returncode == 1, "A malformed tar archive must be rejected"

    missing = tmp_path / "missing.tar"
    assert run_script(missing).returncode == 1, "A nonexistent archive must be rejected"


def test_generated_archives_and_dynamic_ocr_policy(tmp_path):
    original_policy = Path(POLICY_PATH).read_bytes()
    original_mode = os.stat(POLICY_PATH).st_mode

    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    random_part = ''.join(secrets.choice(alphabet) for _ in range(10))
    requested_code = f"DYN-{random_part}"

    try:
        subprocess.run(
            [
                "convert", "-size", "1200x320", "xc:white",
                "-font", "DejaVu-Sans", "-pointsize", "54", "-fill", "black",
                "-draw", "text 30,90 'AUTHORIZED CONFIGURATION POLICY'",
                "-draw", f"text 30,190 'DEPARTMENT_CODE: {requested_code}'",
                POLICY_PATH,
            ],
            check=True,
            capture_output=True,
            timeout=15,
        )
        dynamic_code = policy_code()
        assert dynamic_code == requested_code

        case_dir = tmp_path / secrets.token_hex(8)
        case_dir.mkdir()

        valid = case_dir / f"package-{secrets.token_hex(5)}.tar"
        make_tar(valid, [
            ("settings.conf", f"MODE=production\nDEPT={dynamic_code}\n"),
            ("assets/data.txt", "safe data\n"),
        ])
        assert run_script(valid).returncode == 0, "A newly generated valid archive was rejected"

        invalid_cases = {}

        wrong = case_dir / f"package-{secrets.token_hex(5)}.tar"
        make_tar(wrong, [("settings.conf", "DEPT=OMEGA-77-XRAY\n"), ("data.txt", "safe\n")])
        invalid_cases[wrong] = "wrong department"

        missing = case_dir / f"package-{secrets.token_hex(5)}.tar"
        make_tar(missing, [("data.txt", "safe\n")])
        invalid_cases[missing] = "missing root settings.conf"

        nested = case_dir / f"package-{secrets.token_hex(5)}.tar"
        make_tar(nested, [("config/settings.conf", f"DEPT={dynamic_code}\n")])
        invalid_cases[nested] = "settings.conf not at archive root"

        impostor = case_dir / f"package-{secrets.token_hex(5)}.tar"
        make_tar(impostor, [("settings.conf", f"NOT_DEPT={dynamic_code}\n")])
        invalid_cases[impostor] = "missing exact DEPT key"

        traversal_names = [
            "../escape.txt",
            "../../escape.txt",
            "config/../../escape.txt",
            "some_dir/../escape.txt",
            "..",
        ]
        for member_name in traversal_names:
            archive = case_dir / f"package-{secrets.token_hex(5)}.tar"
            make_tar(archive, [
                ("settings.conf", f"DEPT={dynamic_code}\n"),
                (member_name, "malicious\n"),
            ])
            invalid_cases[archive] = f"traversal member {member_name!r}"

        absolute_escape = tmp_path / f"absolute-escape-{secrets.token_hex(8)}"
        absolute_archive = case_dir / f"package-{secrets.token_hex(5)}.tar"
        make_tar(absolute_archive, [
            ("settings.conf", f"DEPT={dynamic_code}\n"),
            (str(absolute_escape), "malicious\n"),
        ])
        invalid_cases[absolute_archive] = "absolute member path"

        for archive, description in invalid_cases.items():
            result = run_script(archive)
            assert result.returncode == 1, (
                f"Generated invalid archive was not rejected with status 1: {description}; "
                f"got {result.returncode}"
            )

        assert not absolute_escape.exists(), "The validator unsafely extracted an absolute archive member"
    finally:
        Path(POLICY_PATH).write_bytes(original_policy)
        os.chmod(POLICY_PATH, original_mode)


TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
