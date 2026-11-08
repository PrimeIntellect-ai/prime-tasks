#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import struct
import subprocess
import sys
import zipfile
import pytest

SCRIPT_PATH = "/home/user/sanitizer.py"
CLEAN_DIR = "/app/corpora/clean/"
EVIL_DIR = "/app/corpora/evil/"
VENDOR_DIR = "/app/vendor/archivetool"


def corrupt_member_data(path):
    with zipfile.ZipFile(path) as z:
        info = z.infolist()[0]
        header_offset = info.header_offset
    with open(path, "r+b") as f:
        f.seek(header_offset + 26)
        name_len, extra_len = struct.unpack("<HH", f.read(4))
        data_offset = header_offset + 30 + name_len + extra_len
        f.seek(data_offset)
        original = f.read(1)
        assert original, "Archive member has no data to corrupt"
        f.seek(data_offset)
        f.write(bytes([original[0] ^ 0xFF]))
    assert zipfile.is_zipfile(path)
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is not None


def run_sanitizer(path, env=None):
    return subprocess.run(
        [sys.executable, SCRIPT_PATH, str(path)],
        capture_output=True,
        timeout=10,
        env=env,
    )


def test_sanitizer_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Sanitizer script not found at {SCRIPT_PATH}"


def test_vendored_library_is_fixed_and_installed():
    check_code = r'''
import os, struct, tempfile, zipfile
from archivetool import core
assert "ARCHIVETOOL_CONFIG" not in os.environ
with tempfile.TemporaryDirectory() as d:
    good = os.path.join(d, "good.zip")
    with zipfile.ZipFile(good, "w", compression=zipfile.ZIP_STORED) as z:
        z.writestr("payload.bin", b"archive payload")
    assert core.verify_archive(good) is True
    with zipfile.ZipFile(good) as z:
        info = z.infolist()[0]
    with open(good, "r+b") as f:
        f.seek(info.header_offset + 26)
        nl, el = struct.unpack("<HH", f.read(4))
        pos = info.header_offset + 30 + nl + el
        f.seek(pos)
        b = f.read(1)
        f.seek(pos)
        f.write(bytes([b[0] ^ 0xff]))
    assert zipfile.is_zipfile(good)
    assert core.verify_archive(good) is False
    plain = os.path.join(d, "plain.txt")
    open(plain, "wb").write(b"plain text")
    try:
        core.verify_archive(plain)
    except ValueError:
        pass
    else:
        raise AssertionError("Non-archives must not verify as archives")
'''
    env = os.environ.copy()
    env.pop("ARCHIVETOOL_CONFIG", None)

    vendor_code = "import sys; sys.path.insert(0, %r);\n" % VENDOR_DIR + check_code
    vendor = subprocess.run(
        [sys.executable, "-I", "-c", vendor_code],
        cwd="/tmp",
        env=env,
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert vendor.returncode == 0, vendor.stderr

    installed = subprocess.run(
        [sys.executable, "-I", "-c", check_code],
        cwd="/tmp",
        env=env,
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert installed.returncode == 0, "archivetool is not correctly installed: " + installed.stderr


def test_adversarial_corpus():
    assert os.path.isfile(SCRIPT_PATH), f"Sanitizer script not found at {SCRIPT_PATH}"

    # The original setup changed only ZIP timestamp fields. Recreate the intended
    # corpus member and corrupt its data so this file genuinely fails CRC checking.
    corrupt_path = os.path.join(EVIL_DIR, "corrupted_archive.zip")
    with zipfile.ZipFile(corrupt_path, "w", compression=zipfile.ZIP_STORED) as z:
        z.writestr("test.txt", b"evil archive")
    corrupt_member_data(corrupt_path)

    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]

    assert len(clean_files) > 0, f"No clean files found in {CLEAN_DIR}."
    assert len(evil_files) > 0, f"No evil files found in {EVIL_DIR}."

    clean_failures = []
    evil_failures = []

    for f in clean_files:
        res = run_sanitizer(f)
        if res.returncode != 0:
            clean_failures.append(os.path.basename(f))

    for f in evil_files:
        res = run_sanitizer(f)
        if res.returncode != 1:
            evil_failures.append(os.path.basename(f))

    error_msgs = []
    if evil_failures:
        error_msgs.append(f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}")
    if clean_failures:
        error_msgs.append(f"{len(clean_failures)} of {len(clean_files)} clean modified or rejected: {', '.join(clean_failures)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_generated_text_and_archive_cases(tmp_path):
    marker = "[MALICIOUS_MACRO]"
    cases = []

    text_cases = [
        ("utf8-clean", "A harmless UTF-8 document.", "utf-8", 0),
        ("utf8-bad", "prefix " + marker + " suffix", "utf-8", 1),
        ("utf16-clean", "Harmless UTF-16 text Ω.", "utf-16", 0),
        ("utf16-bad", "prefix " + marker + " suffix", "utf-16", 1),
        ("latin1-clean", "Harmless café text.", "iso-8859-1", 0),
        ("latin1-bad", "café " + marker + " fin", "iso-8859-1", 1),
        ("near-marker", "[MALICIOUS-MACRO] is not the exact marker", "utf-8", 0),
    ]
    for index, (_, content, encoding, expected) in enumerate(text_cases):
        path = tmp_path / f"document_{index}_{os.urandom(4).hex()}.dat"
        path.write_bytes(content.encode(encoding))
        cases.append((path, expected))

    utf16be_bad = tmp_path / ("be_" + os.urandom(4).hex())
    utf16be_bad.write_bytes(b"\xfe\xff" + ("before " + marker).encode("utf-16-be"))
    cases.append((utf16be_bad, 1))

    good_zip = tmp_path / ("bundle_" + os.urandom(4).hex())
    with zipfile.ZipFile(good_zip, "w", compression=zipfile.ZIP_DEFLATED) as z:
        z.writestr("content.txt", "A valid archive containing " + marker)
    cases.append((good_zip, 0))

    bad_zip = tmp_path / ("bundle_" + os.urandom(4).hex())
    with zipfile.ZipFile(bad_zip, "w", compression=zipfile.ZIP_STORED) as z:
        z.writestr("payload.bin", os.urandom(64))
    corrupt_member_data(bad_zip)
    cases.append((bad_zip, 1))

    failures = []
    for path, expected in cases:
        result = run_sanitizer(path)
        if result.returncode != expected:
            failures.append(f"{path.name}: expected {expected}, got {result.returncode}")
    assert not failures, " | ".join(failures)


def test_sanitizer_uses_archivetool_and_handles_verifier_failures(tmp_path):
    shadow = tmp_path / "shadow"
    package = shadow / "archivetool"
    package.mkdir(parents=True)
    (package / "__init__.py").write_text("", encoding="utf-8")
    (package / "core.py").write_text(
        "import os\n"
        "def verify_archive(filepath):\n"
        "    with open(os.environ['VERIFY_CALL_LOG'], 'a') as f: f.write(filepath + '\\n')\n"
        "    if os.environ.get('VERIFY_MODE') == 'raise': raise RuntimeError('verification failed')\n"
        "    return False\n",
        encoding="utf-8",
    )

    archive = tmp_path / ("valid_" + os.urandom(4).hex() + ".zip")
    with zipfile.ZipFile(archive, "w") as z:
        z.writestr("file.txt", "valid data")

    for mode in ("false", "raise"):
        log = tmp_path / ("calls_" + mode)
        env = os.environ.copy()
        env["PYTHONPATH"] = str(shadow)
        env["VERIFY_CALL_LOG"] = str(log)
        env["VERIFY_MODE"] = mode
        result = run_sanitizer(archive, env=env)
        assert result.returncode == 1, f"verify_archive {mode} result was not classified malicious"
        assert log.is_file() and str(archive) in log.read_text(), "sanitizer did not call archivetool.core.verify_archive"


def test_exactly_one_argument_is_required():
    no_args = subprocess.run([sys.executable, SCRIPT_PATH], capture_output=True, timeout=10)
    two_args = subprocess.run([sys.executable, SCRIPT_PATH, "one", "two"], capture_output=True, timeout=10)
    assert no_args.returncode != 0
    assert two_args.returncode != 0
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
