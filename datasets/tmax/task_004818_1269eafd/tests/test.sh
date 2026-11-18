#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import re
import secrets
import shlex
import shutil
import stat
import subprocess
import tempfile

import pytest

SCRIPT_PATH = "/home/user/curate_repo.sh"
CONFIG_PATH = "/home/user/repo_config.ini"
REPO_PATH = "/home/user/artifact_repo"
META1_PATH = "/home/user/artifact_repo/groupA/artifact1.meta"
META2_PATH = "/home/user/artifact_repo/groupB/artifact2.meta"


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_logic():
    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        script_content = f.read()

    # Keep the original checks against hardcoding and nominal atomic-write logic.
    assert "C:\\OldSystem\\Binaries\\" not in script_content, \
        "Script should not hardcode the OldPrefix 'C:\\OldSystem\\Binaries\\'."
    assert "/opt/new_system/artifacts/" not in script_content, \
        "Script should not hardcode the NewPrefix '/opt/new_system/artifacts/'."
    assert ".tmp" in script_content, "Script must use a .tmp file for atomic writes."
    assert "mv " in script_content, "Script must use 'mv' to atomically replace the original file."


def test_meta_files_encoded_utf8():
    for meta_path in [META1_PATH, META2_PATH]:
        assert os.path.exists(meta_path), f"File {meta_path} is missing."
        try:
            with open(meta_path, "r", encoding="utf-8") as f:
                content = f.read()
            assert "\x00" not in content, \
                f"File {meta_path} still appears to be UTF-16 encoded (contains null bytes)."
        except UnicodeDecodeError:
            pytest.fail(f"File {meta_path} could not be decoded as UTF-8.")


def test_meta_files_content_updated():
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        config_content = f.read()

    old_prefix = re.search(r"OldPrefix=(.*)", config_content).group(1).strip()
    new_prefix = re.search(r"NewPrefix=(.*)", config_content).group(1).strip()

    with open(META1_PATH, "r", encoding="utf-8") as f:
        content1 = f.read()
    assert old_prefix not in content1, f"Old prefix {old_prefix} still found in {META1_PATH}."
    assert f"Path={new_prefix}groupA/artifact1.bin" in content1, \
        f"New path not correctly set in {META1_PATH}."

    with open(META2_PATH, "r", encoding="utf-8") as f:
        content2 = f.read()
    assert old_prefix not in content2, f"Old prefix {old_prefix} still found in {META2_PATH}."
    assert f"Path={new_prefix}groupB/artifact2.bin" in content2, \
        f"New path not correctly set in {META2_PATH}."


def test_script_executes_dynamic_conversion_for_every_meta_atomically():
    token = secrets.token_hex(12)
    old_prefix = "Z:\\Legacy_" + token + "\\Binaries\\"
    new_prefix = "/srv/migrated_" + token + "/"

    fixtures = {
        "root.meta": (
            "Version=7\n"
            f"Path={old_prefix}root.bin\n"
            f"Mirror={old_prefix}root-copy.bin\n"
            "Label=café\n"
        ),
        "setA/first.meta": (
            "Version=8\n"
            f"Path={old_prefix}first.bin\n"
            f"Notes=from {old_prefix}first.bin and {old_prefix}second.bin\n"
            "Checksum=aa11\n"
        ),
        "setB/deeper/second.meta": (
            "Version=9\n"
            f"Path={old_prefix}second.bin\n"
            "Unicode=雪\n"
            f"Backup={old_prefix}backup.bin\n"
        ),
    }
    expected = {name: text.replace(old_prefix, new_prefix) for name, text in fixtures.items()}

    repo_backup = REPO_PATH + ".verifier-backup-" + token
    config_backup = open(CONFIG_PATH, "rb").read()
    mv_path = os.path.realpath(shutil.which("mv"))
    fd, real_mv = tempfile.mkstemp(prefix="verifier-real-mv-")
    os.close(fd)
    shutil.copy2(mv_path, real_mv)
    os.chmod(real_mv, 0o755)
    helper = "/tmp/check_mv_" + token + ".py"
    log_path = "/tmp/mv_log_" + token + ".jsonl"

    os.rename(REPO_PATH, repo_backup)
    os.makedirs(REPO_PATH)

    try:
        for relative, text in fixtures.items():
            path = os.path.join(REPO_PATH, relative)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(text.encode("utf-16le"))

        # A non-metadata file must not be mistaken for a conversion target.
        with open(os.path.join(REPO_PATH, "leave.dat"), "wb") as f:
            f.write(b"unchanged\x00bytes")

        with open(CONFIG_PATH, "w", encoding="utf-8", newline="\n") as f:
            f.write(f"[Paths]\nOldPrefix={old_prefix}\nNewPrefix={new_prefix}\n")

        with open(helper, "w", encoding="utf-8") as f:
            f.write("""import hashlib, json, os, sys
args = sys.argv[1:]
record = {"valid": False, "args": args}
if len(args) >= 2:
    src, dst = args[-2], args[-1]
    src_abs, dst_abs = os.path.abspath(src), os.path.abspath(dst)
    if src_abs == dst_abs + '.tmp' and os.path.isfile(src_abs):
        with open(src_abs, 'rb') as inp:
            record = {"valid": True, "dst": dst_abs,
                      "sha256": hashlib.sha256(inp.read()).hexdigest()}
with open(os.environ['VERIFIER_MV_LOG'], 'a', encoding='utf-8') as out:
    out.write(json.dumps(record) + '\\n')
""")

        wrapper = (
            "#!/bin/bash\n"
            f"/usr/bin/python3 {shlex.quote(helper)} \"$@\"\n"
            f"exec {shlex.quote(real_mv)} \"$@\"\n"
        )
        with open(mv_path, "w", encoding="utf-8") as f:
            f.write(wrapper)
        os.chmod(mv_path, 0o755)

        env = os.environ.copy()
        env["VERIFIER_MV_LOG"] = log_path
        result = subprocess.run(
            [SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
            timeout=30,
        )
        assert result.returncode == 0, \
            f"Script failed on generated repository. stdout={result.stdout!r} stderr={result.stderr!r}"

        records = []
        if os.path.exists(log_path):
            with open(log_path, "r", encoding="utf-8") as f:
                records = [json.loads(line) for line in f if line.strip()]

        expected_paths = {os.path.abspath(os.path.join(REPO_PATH, name)) for name in fixtures}
        for relative, expected_text in expected.items():
            path = os.path.join(REPO_PATH, relative)
            assert os.path.isfile(path), f"Generated metadata file {path} is missing."
            raw = open(path, "rb").read()
            try:
                actual = raw.decode("utf-8")
            except UnicodeDecodeError:
                pytest.fail(f"Generated metadata file {path} was not converted to UTF-8.")
            assert "\x00" not in actual, f"Generated metadata file {path} still contains null bytes."
            assert actual == expected_text, \
                f"Generated metadata file {path} was not fully converted and replaced."
            assert old_prefix not in actual, f"Old prefix remains in generated metadata file {path}."
            assert not os.path.exists(path + ".tmp"), f"Temporary file {path}.tmp was not moved away."

            wanted_hash = hashlib.sha256(expected_text.encode("utf-8")).hexdigest()
            matching = [r for r in records if r.get("valid") and r.get("dst") == os.path.abspath(path)]
            assert any(r.get("sha256") == wanted_hash for r in matching), \
                f"No mv of the required populated temporary file {path}.tmp onto {path} was observed."

        observed_paths = {r.get("dst") for r in records if r.get("valid")}
        assert expected_paths <= observed_paths, "Not every .meta file was replaced using its same-directory .tmp file."
        assert open(os.path.join(REPO_PATH, "leave.dat"), "rb").read() == b"unchanged\x00bytes"
    finally:
        # Restore the system command and the agent's original final state.
        shutil.copy2(real_mv, mv_path)
        os.chmod(mv_path, stat.S_IMODE(os.stat(real_mv).st_mode))
        if os.path.exists(REPO_PATH):
            shutil.rmtree(REPO_PATH)
        if os.path.exists(repo_backup):
            os.rename(repo_backup, REPO_PATH)
        with open(CONFIG_PATH, "wb") as f:
            f.write(config_backup)
        for path in (real_mv, helper, log_path):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
