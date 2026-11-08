#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import configparser
import secrets
import subprocess
import sys
import textwrap
from pathlib import Path


def test_parser_script_exists():
    """Verify that the parser script was created."""
    script_path = "/home/user/parser.py"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."


def test_json_output_exists():
    """Verify that the JSON output file was created."""
    json_path = "/home/user/safe_extraction_plan.json"
    assert os.path.isfile(json_path), f"The output file {json_path} does not exist."


def test_json_output_content():
    """Verify that the JSON output contains the correct data derived from the manifests."""
    json_path = "/home/user/safe_extraction_plan.json"

    with open(json_path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {json_path} does not contain valid JSON."

    expected_safe_files = sorted([
        "dir/café.txt",
        "dir/file2.txt",
        "file1.txt",
        "legit_file.dat"
    ])
    expected_total_bytes = 1024 + 2048 + 4096 + 100
    expected_malicious_skipped = 2

    assert "total_safe_bytes" in data, "Missing 'total_safe_bytes' in JSON output."
    assert data["total_safe_bytes"] == expected_total_bytes, f"Expected total_safe_bytes to be {expected_total_bytes}, got {data['total_safe_bytes']}."

    assert "safe_files" in data, "Missing 'safe_files' in JSON output."
    assert isinstance(data["safe_files"], list), "'safe_files' should be a list."
    assert data["safe_files"] == expected_safe_files, f"Expected safe_files to be {expected_safe_files}, got {data['safe_files']}."

    assert "malicious_files_skipped" in data, "Missing 'malicious_files_skipped' in JSON output."
    assert data["malicious_files_skipped"] == expected_malicious_skipped, f"Expected malicious_files_skipped to be {expected_malicious_skipped}, got {data['malicious_files_skipped']}."


def test_parser_executes_on_dynamic_manifests_and_uses_atomic_rename(tmp_path):
    token = secrets.token_hex(8)
    config_path = Path("/home/user/config/backup_system.ini")
    data_dir = Path("/home/user/data")
    extract_dir = Path("/home/user/extract")
    output_path = Path("/home/user/safe_extraction_plan.json")

    manifest_utf8 = data_dir / f"dynamic_{token}_utf8.manifest"
    manifest_latin1 = data_dir / f"dynamic_{token}_latin1.manifest"

    size_a = 1100 + secrets.randbelow(700)
    size_b = 2100 + secrets.randbelow(700)
    size_c = 3100 + secrets.randbelow(700)

    safe_a = f"alpha_{token}.bin"
    safe_b = f"nested/../beta_{token}.dat"
    safe_c = f"dir/café_{token}.txt"
    symlink_name = f"link_{token}"
    symlink_path = extract_dir / symlink_name
    outside_dir = Path("/tmp") / f"outside_{token}"
    outside_dir.mkdir(parents=True, exist_ok=True)
    symlink_path.symlink_to(outside_dir, target_is_directory=True)

    manifest_utf8.write_text(
        f"{safe_a} {size_a}\n"
        f"{safe_b} {size_b}\n"
        f"../escape_{token}.txt 17\n"
        f"/tmp/absolute_{token}.txt 19\n",
        encoding="utf-8",
    )
    with open(manifest_latin1, "wb") as f:
        f.write(f"{safe_c} {size_c}\n".encode("iso-8859-1"))
        f.write(f"{symlink_name}/payload.txt 23\n".encode("iso-8859-1"))

    config_path.write_text(
        "[manifests]\n"
        f"{manifest_utf8} = utf-8\n"
        f"{manifest_latin1} = iso-8859-1\n",
        encoding="utf-8",
    )

    if output_path.exists() or output_path.is_symlink():
        output_path.unlink()

    trace_path = tmp_path / "filesystem_trace.jsonl"
    hook_dir = tmp_path / "hook"
    hook_dir.mkdir()
    (hook_dir / "sitecustomize.py").write_text(textwrap.dedent(r'''
        import builtins
        import io
        import json
        import os

        _trace = os.environ.get("PARSER_TRACE_FILE")
        _final = os.path.abspath("/home/user/safe_extraction_plan.json")
        _real_builtin_open = builtins.open
        _real_io_open = io.open
        _real_os_open = os.open
        _real_replace = os.replace
        _real_rename = os.rename

        def _path(value):
            if isinstance(value, int):
                return None
            try:
                return os.path.abspath(os.fsdecode(value))
            except (TypeError, ValueError):
                return None

        def _log(event):
            if not _trace:
                return
            with _real_builtin_open(_trace, "a", encoding="utf-8") as stream:
                stream.write(json.dumps(event, ensure_ascii=False) + "\n")

        def _is_write_mode(mode):
            mode = str(mode)
            return any(ch in mode for ch in "wax+")

        def traced_builtin_open(file, mode="r", *args, **kwargs):
            path = _path(file)
            if path == _final and _is_write_mode(mode):
                _log({"op": "direct_final_write", "path": path})
            return _real_builtin_open(file, mode, *args, **kwargs)

        def traced_io_open(file, mode="r", *args, **kwargs):
            path = _path(file)
            if path == _final and _is_write_mode(mode):
                _log({"op": "direct_final_write", "path": path})
            return _real_io_open(file, mode, *args, **kwargs)

        def traced_os_open(file, flags, *args, **kwargs):
            path = _path(file)
            write_flags = os.O_WRONLY | os.O_RDWR | os.O_CREAT | os.O_TRUNC | os.O_APPEND
            if path == _final and flags & write_flags:
                _log({"op": "direct_final_write", "path": path})
            return _real_os_open(file, flags, *args, **kwargs)

        def traced_replace(src, dst, *args, **kwargs):
            event = {"op": "replace", "src": _path(src), "dst": _path(dst),
                     "src_existed": os.path.isfile(src)}
            result = _real_replace(src, dst, *args, **kwargs)
            _log(event)
            return result

        def traced_rename(src, dst, *args, **kwargs):
            event = {"op": "rename", "src": _path(src), "dst": _path(dst),
                     "src_existed": os.path.isfile(src)}
            result = _real_rename(src, dst, *args, **kwargs)
            _log(event)
            return result

        builtins.open = traced_builtin_open
        io.open = traced_io_open
        os.open = traced_os_open
        os.replace = traced_replace
        os.rename = traced_rename
    '''), encoding="utf-8")

    env = os.environ.copy()
    env["PARSER_TRACE_FILE"] = str(trace_path)
    env["PYTHONPATH"] = str(hook_dir) + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    result = subprocess.run(
        [sys.executable, "/home/user/parser.py"],
        cwd="/home/user",
        env=env,
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert result.returncode == 0, f"parser.py failed:\nstdout: {result.stdout}\nstderr: {result.stderr}"
    assert output_path.is_file(), "Executing parser.py did not create the output JSON."

    raw = output_path.read_bytes()
    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise AssertionError(f"Dynamic output is not valid UTF-8 JSON: {exc}")

    expected_files = sorted([safe_a, safe_b, safe_c])
    assert set(data) == {"total_safe_bytes", "safe_files", "malicious_files_skipped"}
    assert type(data["total_safe_bytes"]) is int
    assert data["total_safe_bytes"] == size_a + size_b + size_c
    assert data["safe_files"] == expected_files
    assert all(type(item) is str for item in data["safe_files"])
    assert type(data["malicious_files_skipped"]) is int
    assert data["malicious_files_skipped"] == 3

    assert trace_path.is_file(), "No filesystem trace was produced while parser.py ran."
    events = [json.loads(line) for line in trace_path.read_text(encoding="utf-8").splitlines() if line]
    assert not any(event.get("op") == "direct_final_write" for event in events), \
        "The final JSON was opened for direct writing instead of being installed atomically."
    atomic_events = [
        event for event in events
        if event.get("op") in {"replace", "rename"}
        and event.get("dst") == str(output_path)
        and event.get("src") != str(output_path)
        and event.get("src_existed") is True
    ]
    assert atomic_events, "parser.py did not atomically rename a temporary file to the final output path."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
