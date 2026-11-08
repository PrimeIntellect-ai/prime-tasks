#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import zlib
import hashlib
import subprocess
import sys
import secrets
import stat
import pytest

DOCPACK_PATH = "/home/user/release.docpack"
DOCS_DIR = "/home/user/docs_raw"
SCRIPT_PATH = "/home/user/pack_docs.py"


def test_pack_script_exists_and_is_regular_file():
    assert os.path.exists(SCRIPT_PATH), f"The required script {SCRIPT_PATH} was not found."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} should be a regular file."
    assert not os.path.islink(SCRIPT_PATH), f"{SCRIPT_PATH} should not be a symbolic link."
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} should be a regular file."


def test_docpack_exists():
    assert os.path.exists(DOCPACK_PATH), f"The final archive {DOCPACK_PATH} was not found."
    assert os.path.isfile(DOCPACK_PATH), f"{DOCPACK_PATH} should be a file."


def test_no_temp_files():
    temp_file = "/home/user/release.tmp"
    assert not os.path.exists(temp_file), f"Temporary file {temp_file} was left behind."


def test_docpack_content_and_structure():
    assert os.path.exists(DOCPACK_PATH), "Docpack missing."

    with open(DOCPACK_PATH, "rb") as f:
        compressed_data = f.read()

    try:
        decompressed_data = zlib.decompress(compressed_data).decode('utf-8')
    except Exception as e:
        pytest.fail(f"Failed to decompress or decode the archive: {e}")

    try:
        data = json.loads(decompressed_data)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse JSON from the decompressed archive: {e}")

    assert "manifest" in data, "The 'manifest' key is missing from the JSON object."
    assert "files" in data, "The 'files' key is missing from the JSON object."

    assert isinstance(data["manifest"], dict), "'manifest' should be a dictionary."
    assert isinstance(data["files"], dict), "'files' should be a dictionary."


def test_docpack_transformed_files_and_manifest():
    assert os.path.exists(DOCPACK_PATH), "Docpack missing."

    with open(DOCPACK_PATH, "rb") as f:
        data = json.loads(zlib.decompress(f.read()).decode('utf-8'))

    files = data.get("files", {})
    manifest = data.get("manifest", {})

    expected_original_files = ["intro.md", "setup.md", "api.md"]

    for filename in expected_original_files:
        assert filename in files, f"File {filename} is missing from the 'files' object."
        assert filename in manifest, f"File {filename} is missing from the 'manifest' object."

        content = files[filename]

        assert "AcmeCorp" not in content, f"'AcmeCorp' was not replaced in {filename}."
        assert "v1.0" not in content, f"'v1.0' was not replaced in {filename}."
        assert "ZenithInc" in content, f"'ZenithInc' was not found in {filename}."
        assert "v2.0" in content, f"'v2.0' was not found in {filename}."

        expected_hash = hashlib.sha256(content.encode('utf-8')).hexdigest()
        assert manifest[filename] == expected_hash, f"The manifest hash for {filename} is incorrect."


def test_exact_transformed_content():
    assert os.path.exists(DOCPACK_PATH), "Docpack missing."

    with open(DOCPACK_PATH, "rb") as f:
        data = json.loads(zlib.decompress(f.read()).decode('utf-8'))

    files = data.get("files", {})

    expected_content = {
        "intro.md": "Welcome to ZenithInc API v2.0. This is the intro to ZenithInc.\n",
        "setup.md": "To setup ZenithInc software v2.0, run the installer. ZenithInc rocks.\n",
        "api.md": "ZenithInc v2.0 has 5 endpoints. Contact ZenithInc support.\n"
    }

    for filename, expected_text in expected_content.items():
        if filename in files:
            assert files[filename] == expected_text, f"The transformed content of {filename} does not exactly match expectations."


def test_script_handles_fresh_inputs_and_publishes_by_atomic_rename(tmp_path):
    token = secrets.token_hex(12)
    fresh_name = f"fresh_{token}.md"
    raw_contents = {
        "intro.md": f"AcmeCorp v1.0 dynamic intro {token}. AcmeCorp.\n",
        "setup.md": f"Setup {token}: v1.0 for AcmeCorp, then AcmeCorp again.\n",
        "api.md": f"{token} AcmeCorp API v1.0.\nSecond line v1.0 AcmeCorp.\n",
        fresh_name: f"New file {token}: AcmeCorp v1.0 and AcmeCorp v1.0.\n",
    }

    for name in os.listdir(DOCS_DIR):
        path = os.path.join(DOCS_DIR, name)
        if os.path.isfile(path):
            os.unlink(path)
    for name, content in raw_contents.items():
        with open(os.path.join(DOCS_DIR, name), "w", encoding="utf-8") as f:
            f.write(content)
    with open(os.path.join(DOCS_DIR, f"ignored_{token}.txt"), "w", encoding="utf-8") as f:
        f.write("AcmeCorp v1.0 must not be archived")

    if os.path.lexists(DOCPACK_PATH):
        os.unlink(DOCPACK_PATH)
    temp_file = "/home/user/release.tmp"
    if os.path.lexists(temp_file):
        os.unlink(temp_file)

    hook_dir = tmp_path / "hook"
    hook_dir.mkdir()
    event_log = tmp_path / "events.log"
    sitecustomize = hook_dir / "sitecustomize.py"
    sitecustomize.write_text(
        '''import os\n\nTARGET = os.path.normpath(os.path.abspath("/home/user/release.docpack"))\nLOG = os.environ["PACK_DOCS_EVENT_LOG"]\n_busy = False\n\ndef _path(value):\n    try:\n        return os.path.normpath(os.path.abspath(os.fspath(value)))\n    except Exception:\n        return ""\n\ndef _record(line):\n    global _busy\n    if _busy:\n        return\n    _busy = True\n    try:\n        with open(LOG, "a", encoding="utf-8") as f:\n            f.write(line + "\\n")\n    finally:\n        _busy = False\n\ndef _audit(event, args):\n    if _busy:\n        return\n    if event == "open":\n        path = _path(args[0])\n        mode = args[1]\n        flags = args[2]\n        writing = (isinstance(mode, str) and any(c in mode for c in "wax+")) or (isinstance(flags, int) and bool(flags & (os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND)))\n        if path == TARGET and writing:\n            _record("DIRECT_WRITE")\n    elif event == "os.rename":\n        src, dst = args[0], args[1]\n        if _path(dst) == TARGET:\n            src_path = _path(src)\n            _record("RENAME|%s|%d|%d" % (src_path, os.path.isfile(src_path), os.path.exists(TARGET)))\n\nimport sys\nsys.addaudithook(_audit)\n''',
        encoding="utf-8",
    )

    env = os.environ.copy()
    env["PYTHONPATH"] = str(hook_dir)
    env["PACK_DOCS_EVENT_LOG"] = str(event_log)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"pack_docs.py failed on fresh inputs:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(DOCPACK_PATH), "The script did not generate release.docpack on fresh inputs."

    events = event_log.read_text(encoding="utf-8").splitlines() if event_log.exists() else []
    assert "DIRECT_WRITE" not in events, "The script wrote directly to release.docpack instead of publishing it only by rename."
    renames = [line for line in events if line.startswith("RENAME|")]
    assert renames, "No atomic rename to release.docpack was observed."
    valid_renames = []
    for line in renames:
        _, source, source_existed, destination_existed = line.split("|", 3)
        if source != DOCPACK_PATH and source_existed == "1" and destination_existed == "0":
            valid_renames.append(source)
    assert valid_renames, "release.docpack was not atomically renamed from an existing temporary file."
    assert all(not os.path.exists(source) for source in valid_renames), "A temporary source file was left behind."
    assert not os.path.exists(temp_file), f"Temporary file {temp_file} was left behind."

    try:
        with open(DOCPACK_PATH, "rb") as f:
            data = json.loads(zlib.decompress(f.read()).decode("utf-8"))
    except Exception as e:
        pytest.fail(f"Freshly generated archive is invalid: {e}")

    expected_files = {
        name: content.replace("AcmeCorp", "ZenithInc").replace("v1.0", "v2.0")
        for name, content in raw_contents.items()
    }
    expected_manifest = {
        name: hashlib.sha256(content.encode("utf-8")).hexdigest()
        for name, content in expected_files.items()
    }
    assert set(data.keys()) == {"manifest", "files"}, "The JSON object must contain exactly 'manifest' and 'files'."
    assert data["files"] == expected_files, "The script did not archive exactly the freshly derived transformed Markdown contents."
    assert data["manifest"] == expected_manifest, "The manifest for the fresh inputs is incorrect."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
