#!/bin/bash
set -e
mkdir -p /logs/verifier

cp /home/user/tracker_config.ini /tmp/tracker_config.ini.original
cp /home/user/backup.tar /tmp/backup.tar.original
cleanup() {
    cp /tmp/tracker_config.ini.original /home/user/tracker_config.ini
    cp /tmp/backup.tar.original /home/user/backup.tar
    rm -rf /tmp/config_tracker_verify_*
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import io
import json
import os
import secrets
import subprocess
import tarfile
import tempfile
import textwrap
import pytest

SCRIPT = "/home/user/config_tracker.py"
MANIFEST = "/home/user/manifest.json"
ALERTS = "/home/user/security_alerts.log"


def test_script_exists_and_is_python():
    assert os.path.isfile(SCRIPT), f"Tracker script missing or not a regular file: {SCRIPT}"
    assert not os.path.islink(SCRIPT), f"Tracker script must not be a symbolic link: {SCRIPT}"
    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    assert source.strip(), "Tracker script is empty."
    try:
        ast.parse(source, filename=SCRIPT)
    except SyntaxError as exc:
        pytest.fail(f"Tracker script is not valid Python: {exc}")


def test_manifest_json():
    manifest_path = "/home/user/manifest.json"
    assert os.path.exists(manifest_path), f"Manifest file missing: {manifest_path}"

    with open(manifest_path, "r") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Manifest file is not valid JSON: {manifest_path}")

    # Compute expected hashes
    content1 = b"server { listen 80; }"
    content3 = b'{"key": "value"}'

    hash1 = hashlib.sha256(content1).hexdigest()
    hash3 = hashlib.sha256(content3).hexdigest()

    expected_manifest = {
        "/home/user/extracted/nginx/valid1.conf": hash1,
        "/home/user/extracted/app/valid3.json": hash3
    }

    assert isinstance(manifest, dict), "Manifest should be a JSON dictionary."
    assert len(manifest) == len(expected_manifest), f"Manifest should contain exactly {len(expected_manifest)} entries."

    for key, expected_hash in expected_manifest.items():
        assert key in manifest, f"Missing expected file path in manifest: {key}"
        assert manifest[key] == expected_hash, f"Incorrect hash for {key}. Expected {expected_hash}, got {manifest[key]}"


def test_security_alerts_log():
    log_path = "/home/user/security_alerts.log"
    assert os.path.exists(log_path), f"Security alerts log missing: {log_path}"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_alerts = {
        "ALERT: Path traversal detected - /etc/cron.d/mal1.sh",
        "ALERT: Path traversal detected - ../ssh/mal2.conf",
        "ALERT: Path traversal detected - nginx/../../mal3.xml"
    }

    actual_alerts = set(lines)

    missing = expected_alerts - actual_alerts
    extra = actual_alerts - expected_alerts

    assert not missing, f"Missing expected security alerts: {missing}"
    assert not extra, f"Unexpected security alerts found: {extra}"
    assert len(lines) == len(expected_alerts), "Log contains duplicate or extra lines not accounted for."


def _add_file(tar, name, content):
    info = tarfile.TarInfo(name=name)
    info.size = len(content)
    info.mode = 0o644
    tar.addfile(info, io.BytesIO(content))


def test_executes_tracker_on_derived_fixture_using_streaming_mode():
    token = secrets.token_hex(8)
    verify_dir = tempfile.mkdtemp(prefix="config_tracker_verify_", dir="/tmp")
    target_dir = os.path.join(verify_dir, "target")
    sibling_dir = os.path.join(verify_dir, f"target_evil_{token}")
    absolute_canary = os.path.join("/tmp", f"config_tracker_abs_{token}.cfgx")
    marker = os.path.join(verify_dir, "streaming.marker")
    hook_dir = os.path.join(verify_dir, "hook")
    os.mkdir(hook_dir)

    safe_name_1 = f"services/{token}.cfgx"
    safe_name_2 = f"data/{token}.json"
    excluded_name = f"notes/{token}.conf"
    sibling_attack = f"../{os.path.basename(sibling_dir)}/pwn.cfgx"
    absolute_attack = absolute_canary

    safe_content_1 = secrets.token_bytes(257)
    safe_content_2 = secrets.token_bytes(509)
    excluded_content = secrets.token_bytes(83)

    with open("/home/user/tracker_config.ini", "w", encoding="utf-8") as f:
        f.write("[Settings]\n")
        f.write(f"target_dir = {target_dir}\n")
        f.write("allowed_exts = .cfgx,.json\n")

    with tarfile.open("/home/user/backup.tar", "w") as tar:
        _add_file(tar, safe_name_1, safe_content_1)
        _add_file(tar, excluded_name, excluded_content)
        _add_file(tar, sibling_attack, b"sibling traversal")
        _add_file(tar, safe_name_2, safe_content_2)
        _add_file(tar, absolute_attack, b"absolute traversal")

    sitecustomize = textwrap.dedent(f'''\
        import os
        import tarfile

        _marker = {marker!r}
        _archive = os.path.realpath('/home/user/backup.tar')
        _module_open = tarfile.open
        _class_open_func = tarfile.TarFile.open.__func__

        def _check(name, mode):
            try:
                relevant = os.path.realpath(os.fspath(name)) == _archive
            except (TypeError, ValueError):
                relevant = False
            if relevant:
                if not isinstance(mode, str) or not mode.startswith('r|'):
                    raise RuntimeError('backup.tar must be opened in tar streaming read mode')
                with open(_marker, 'a', encoding='utf-8') as marker_file:
                    marker_file.write(mode + '\\n')

        def checked_open(name=None, mode='r', fileobj=None, bufsize=10240, **kwargs):
            _check(name, mode)
            return _module_open(name=name, mode=mode, fileobj=fileobj, bufsize=bufsize, **kwargs)

        def checked_class_open(cls, name=None, mode='r', fileobj=None, bufsize=10240, **kwargs):
            _check(name, mode)
            return _class_open_func(cls, name=name, mode=mode, fileobj=fileobj, bufsize=bufsize, **kwargs)

        def forbidden_extract(*args, **kwargs):
            raise RuntimeError('archive extraction to disk is forbidden')

        tarfile.open = checked_open
        tarfile.TarFile.open = classmethod(checked_class_open)
        tarfile.TarFile.extract = forbidden_extract
        tarfile.TarFile.extractall = forbidden_extract
    ''')
    with open(os.path.join(hook_dir, "sitecustomize.py"), "w", encoding="utf-8") as f:
        f.write(sitecustomize)

    for path in (MANIFEST, ALERTS, absolute_canary):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["PYTHONPATH"] = hook_dir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    result = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Tracker failed on a verifier-generated archive (exit {result.returncode}).\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(marker), "Tracker did not open backup.tar through tarfile streaming mode."

    assert os.path.isfile(MANIFEST), "Tracker did not create manifest.json when executed."
    with open(MANIFEST, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    expected_manifest = {
        os.path.join(target_dir, safe_name_1): hashlib.sha256(safe_content_1).hexdigest(),
        os.path.join(target_dir, safe_name_2): hashlib.sha256(safe_content_2).hexdigest(),
    }
    assert isinstance(manifest, dict), "Generated manifest must be a flat JSON dictionary."
    assert manifest == expected_manifest, "Tracker did not derive the correct manifest from the generated archive and config."

    assert os.path.isfile(ALERTS), "Tracker did not create security_alerts.log when executed."
    with open(ALERTS, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]
    expected_alerts = {
        f"ALERT: Path traversal detected - {sibling_attack}",
        f"ALERT: Path traversal detected - {absolute_attack}",
    }
    assert set(lines) == expected_alerts, "Tracker produced incorrect traversal alerts for the generated archive."
    assert len(lines) == len(expected_alerts), "Traversal log contains duplicate or extra lines."

    assert not os.path.exists(target_dir), "Tracker extracted files into target_dir instead of processing the tar stream."
    assert not os.path.exists(sibling_dir), "Tracker wrote a path-traversal entry outside target_dir."
    assert not os.path.exists(absolute_canary), "Tracker wrote an absolute-path archive entry to disk."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
