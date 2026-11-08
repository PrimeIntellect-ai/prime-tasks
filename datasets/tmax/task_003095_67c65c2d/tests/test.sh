#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import copy
import json
import os
import secrets
import subprocess
import textwrap
import pytest

CONFIG_DIR = "/home/user/config_backups"
AUDIT_LOG = "/home/user/redaction_audit.log"
MASTER_JSON = "/home/user/master_config.json"
CONSOLIDATE_SCRIPT = "/home/user/consolidate.py"

EXPECTED_DATA = {
    "app_server.cfg": {
        "host": "127.0.0.1",
        "port": "8080",
        "API_KEY": "REDACTED",
        "max_connections": "500",
        "timeout": "30",
        "password": "REDACTED"
    },
    "cache.cfg": {
        "engine": "redis",
        "memory": "2G",
        "Password": "REDACTED"
    },
    "db_config.ini": {
        "database": {
            "engine": "postgres",
            "host": "10.0.0.5"
        },
        "credentials": {
            "username": "admin",
            "password": "REDACTED",
            "api_key": "REDACTED"
        }
    }
}

def test_phase1_merging():
    merged_file = os.path.join(CONFIG_DIR, "app_server.cfg")
    assert os.path.isfile(merged_file), f"Merged file {merged_file} does not exist."

    for i in range(1, 4):
        part_file = os.path.join(CONFIG_DIR, f"app_server.part{i}.cfg")
        assert not os.path.exists(part_file), f"Part file {part_file} was not deleted."

def test_phase1_renaming():
    db_ini = os.path.join(CONFIG_DIR, "db_config.ini")
    db_txt = os.path.join(CONFIG_DIR, "db_config.txt")
    notes_txt = os.path.join(CONFIG_DIR, "notes.txt")

    assert os.path.isfile(db_ini), f"File {db_ini} does not exist. Renaming failed."
    assert not os.path.exists(db_txt), f"File {db_txt} still exists. It should have been renamed."
    assert os.path.isfile(notes_txt), f"File {notes_txt} should not have been renamed or deleted."

def test_phase2_redaction_audit_log():
    assert os.path.isfile(AUDIT_LOG), f"Audit log {AUDIT_LOG} does not exist."

    with open(AUDIT_LOG, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_entries = [
        "app_server.cfg:5:API_KEY",
        "app_server.cfg:8:password",
        "db_config.ini:7:password",
        "db_config.ini:8:api_key",
        "cache.cfg:4:Password"
    ]

    for entry in expected_entries:
        assert entry in lines, f"Expected entry '{entry}' not found in {AUDIT_LOG}"

    assert len(lines) == len(expected_entries), f"Audit log contains unexpected entries: {lines}"

def test_phase2_file_contents_redacted():
    app_server = os.path.join(CONFIG_DIR, "app_server.cfg")
    with open(app_server, "r") as f:
        content = f.read()
    assert "API_KEY=REDACTED" in content, "app_server.cfg was not properly redacted for API_KEY"
    assert "password=REDACTED" in content, "app_server.cfg was not properly redacted for password"

    db_ini = os.path.join(CONFIG_DIR, "db_config.ini")
    with open(db_ini, "r") as f:
        content = f.read()
    assert "password=REDACTED" in content, "db_config.ini was not properly redacted for password"
    assert "api_key=REDACTED" in content, "db_config.ini was not properly redacted for api_key"

    cache_cfg = os.path.join(CONFIG_DIR, "cache.cfg")
    with open(cache_cfg, "r") as f:
        content = f.read()
    assert "Password=REDACTED" in content, "cache.cfg was not properly redacted for Password"

def test_phase3_master_json_contents():
    assert os.path.isfile(MASTER_JSON), f"Master JSON file {MASTER_JSON} does not exist."

    with open(MASTER_JSON, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {MASTER_JSON} is not valid JSON.")

    assert data == EXPECTED_DATA, f"JSON data in {MASTER_JSON} does not match expected output."

def test_phase3_atomic_write_script():
    assert os.path.isfile(CONSOLIDATE_SCRIPT), f"Python script {CONSOLIDATE_SCRIPT} is missing."

    with open(CONSOLIDATE_SCRIPT, "r") as f:
        content = f.read()

    assert "master_config.json.tmp" in content, "Script does not appear to use the required temporary file for atomic writing."
    assert "rename" in content or "replace" in content, "Script does not appear to use an atomic rename operation."

def test_consolidate_executes_parses_dynamic_files_and_writes_atomically(tmp_path):
    token = secrets.token_hex(8)
    cfg_name = f"probe_{token}.cfg"
    ini_name = f"probe_{token}.ini"
    cfg_path = os.path.join(CONFIG_DIR, cfg_name)
    ini_path = os.path.join(CONFIG_DIR, ini_name)
    cfg_value = f"cfg_{secrets.token_hex(10)}"
    ini_value = f"ini_{secrets.token_hex(10)}"
    section = f"section_{token}"

    with open(cfg_path, "w") as f:
        f.write(f"# verifier probe\nprobe_key={cfg_value}\ncount=731\n")
    with open(ini_path, "w") as f:
        f.write(f"[{section}]\nprobe_key={ini_value}\nenabled=yes\n")

    hook_dir = tmp_path / "hook"
    hook_dir.mkdir()
    trace = tmp_path / "atomic.trace"
    hook = hook_dir / "sitecustomize.py"
    hook.write_text(textwrap.dedent(f'''\
        import builtins
        import io
        import os

        FINAL = {MASTER_JSON!r}
        TEMP = {MASTER_JSON + '.tmp'!r}
        TRACE = {str(trace)!r}
        _open = builtins.open
        _io_open = io.open
        _os_open = os.open
        _rename = os.rename
        _replace = os.replace

        def _path(value):
            try:
                return os.path.abspath(os.fspath(value))
            except TypeError:
                return None

        def _log(message):
            with _open(TRACE, 'a') as stream:
                stream.write(message + '\\n')

        def _record_file_write(file, mode):
            path = _path(file)
            if path == FINAL and any(c in mode for c in 'wax+'):
                _log('FINAL_WRITE')
            if path == TEMP and any(c in mode for c in 'wax+'):
                _log('TEMP_WRITE')

        def checked_open(file, mode='r', *args, **kwargs):
            _record_file_write(file, mode)
            return _open(file, mode, *args, **kwargs)

        def checked_io_open(file, mode='r', *args, **kwargs):
            _record_file_write(file, mode)
            return _io_open(file, mode, *args, **kwargs)

        def checked_os_open(file, flags, *args, **kwargs):
            path = _path(file)
            write_flags = os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND
            if flags & write_flags:
                if path == FINAL:
                    _log('FINAL_WRITE')
                if path == TEMP:
                    _log('TEMP_WRITE')
            return _os_open(file, flags, *args, **kwargs)

        def _record_rename(src, dst):
            if _path(src) == TEMP and _path(dst) == FINAL and os.path.isfile(TEMP):
                _log('ATOMIC_RENAME')

        def checked_rename(src, dst, *args, **kwargs):
            _record_rename(src, dst)
            return _rename(src, dst, *args, **kwargs)

        def checked_replace(src, dst, *args, **kwargs):
            _record_rename(src, dst)
            return _replace(src, dst, *args, **kwargs)

        builtins.open = checked_open
        io.open = checked_io_open
        os.open = checked_os_open
        os.rename = checked_rename
        os.replace = checked_replace
    '''))

    for path in (MASTER_JSON, MASTER_JSON + ".tmp"):
        if os.path.lexists(path):
            if os.path.isdir(path):
                pytest.fail(f"Expected output path is a directory: {path}")
            os.unlink(path)

    env = os.environ.copy()
    env["PYTHONPATH"] = str(hook_dir)
    result = subprocess.run(
        ["python3", CONSOLIDATE_SCRIPT],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"consolidate.py failed when executed. stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    assert os.path.isfile(MASTER_JSON), "Executing consolidate.py did not create master_config.json"

    with open(MASTER_JSON, "r") as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"consolidate.py produced invalid JSON: {exc}")

    expected = copy.deepcopy(EXPECTED_DATA)
    expected[cfg_name] = {"probe_key": cfg_value, "count": "731"}
    expected[ini_name] = {section: {"probe_key": ini_value, "enabled": "yes"}}
    assert actual == expected, "consolidate.py did not parse the dynamically supplied cfg/ini files"

    events = trace.read_text().splitlines() if trace.exists() else []
    assert "TEMP_WRITE" in events, "consolidate.py did not write master_config.json.tmp"
    assert "ATOMIC_RENAME" in events, "consolidate.py did not atomically rename the required temporary file"
    assert "FINAL_WRITE" not in events, "consolidate.py wrote directly to master_config.json before renaming"

    os.unlink(cfg_path)
    os.unlink(ini_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
