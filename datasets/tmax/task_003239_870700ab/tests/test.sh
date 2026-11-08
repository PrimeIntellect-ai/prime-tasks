#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import json
import os
import runpy
import stat
import sys
import uuid
from pathlib import Path

INCOMING = Path("/home/user/backups/incoming")
ALLOWED_ROOT = Path("/home/user/data").resolve()
CSV_PATH = Path("/home/user/backups/processed_manifest.csv")
TXT_PATH = Path("/home/user/backups/valid_ids.txt")
SCRIPT_PATH = Path("/home/user/process_backups.py")


def get_expected_valid_paths():
    """Derive expected valid paths from the current incoming manifests."""
    valid_entries = []
    if not INCOMING.exists():
        return valid_entries

    for json_file in INCOMING.rglob("*.json"):
        try:
            with json_file.open("r") as f:
                data = json.load(f)

            backup_id = data.get("backup_id")
            files = data.get("files", [])
            for file_path in files:
                if not os.path.isabs(file_path):
                    full_path = ALLOWED_ROOT / file_path
                else:
                    full_path = Path(file_path)

                resolved_path = full_path.resolve()
                try:
                    resolved_path.relative_to(ALLOWED_ROOT)
                    valid_entries.append((backup_id, str(resolved_path)))
                except ValueError:
                    pass
        except Exception:
            pass

    valid_entries.sort(key=lambda x: (x[0], x[1]))
    return valid_entries


def read_csv_entries():
    with CSV_PATH.open("r", newline="") as f:
        rows = list(csv.reader(f))
    assert rows, "CSV file is empty"
    assert rows[0] == ["backup_id", "valid_file_path"], "CSV header is missing or incorrect"
    return [tuple(row) for row in rows[1:]]


def test_csv_output():
    assert CSV_PATH.exists(), f"CSV file does not exist at {CSV_PATH}"
    actual_entries = read_csv_entries()
    expected_entries = get_expected_valid_paths()
    assert actual_entries == expected_entries, (
        f"CSV content mismatch.\nExpected: {expected_entries}\nGot: {actual_entries}"
    )


def test_txt_output():
    assert TXT_PATH.exists(), f"TXT file does not exist at {TXT_PATH}"
    assert TXT_PATH.is_file() and not TXT_PATH.is_symlink(), "valid_ids.txt must be a regular file"

    expected_entries = get_expected_valid_paths()
    expected_ids = sorted(set(entry[0] for entry in expected_entries))
    with TXT_PATH.open("r") as f:
        actual_ids = [line.strip() for line in f if line.strip()]

    assert actual_ids == expected_ids, (
        f"TXT content mismatch.\nExpected: {expected_ids}\nGot: {actual_ids}"
    )
    assert TXT_PATH.stat().st_mtime_ns >= CSV_PATH.stat().st_mtime_ns, (
        "valid_ids.txt must be produced after the CSV transformation input"
    )


def test_python_script_exists():
    assert SCRIPT_PATH.exists(), f"Python script does not exist at {SCRIPT_PATH}"
    mode = SCRIPT_PATH.lstat().st_mode
    assert stat.S_ISREG(mode) and not SCRIPT_PATH.is_symlink(), "Python script must be a regular file"
    assert SCRIPT_PATH.stat().st_size > 0, "Python script is empty"


def test_script_implements_and_executes_atomic_processing():
    source = SCRIPT_PATH.read_text()
    tree = ast.parse(source, filename=str(SCRIPT_PATH))

    imported_replace_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module == "os":
            for alias in node.names:
                if alias.name == "replace":
                    imported_replace_names.add(alias.asname or alias.name)

    has_os_replace_call = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if (
            isinstance(func, ast.Attribute)
            and func.attr == "replace"
            and isinstance(func.value, ast.Name)
            and func.value.id == "os"
        ) or (isinstance(func, ast.Name) and func.id in imported_replace_names):
            has_os_replace_call = True
            break
    assert has_os_replace_call, "The script must call os.replace for the final atomic rename"

    token = uuid.uuid4().hex
    dynamic_id = f"job-hidden-{token}"
    dynamic_dir = INCOMING / f"verify-{token}"
    dynamic_manifest = dynamic_dir / "manifest.json"
    dynamic_dir.mkdir(parents=True)
    dynamic_manifest.write_text(json.dumps({
        "backup_id": dynamic_id,
        "files": [
            f"project/{token}.txt",
            f"project/../images/{token}.png",
            "../../../../etc/shadow",
            f"/home/user/data/valid_nested/../valid_nested/{token}.dat",
            f"/home/user/data_backup/{token}.txt"
        ]
    }))

    old_csv = CSV_PATH.read_bytes() if CSV_PATH.exists() else None
    old_txt = TXT_PATH.read_bytes() if TXT_PATH.exists() else None
    old_txt_stat = TXT_PATH.stat() if TXT_PATH.exists() else None
    rename_events = []
    original_argv = sys.argv[:]
    original_cwd = os.getcwd()

    def audit_hook(event, args):
        if event == "os.rename" and len(args) >= 2:
            try:
                src = Path(os.fsdecode(args[0]))
                dst = Path(os.fsdecode(args[1]))
                cwd = Path.cwd()
                if not src.is_absolute():
                    src = cwd / src
                if not dst.is_absolute():
                    dst = cwd / dst
                rename_events.append((src.resolve(strict=False), dst.resolve(strict=False)))
            except Exception:
                pass

    try:
        if CSV_PATH.exists():
            CSV_PATH.unlink()

        sys.addaudithook(audit_hook)
        sys.argv = [str(SCRIPT_PATH)]
        try:
            runpy.run_path(str(SCRIPT_PATH), run_name="__main__")
        except SystemExit as exc:
            assert exc.code in (None, 0), f"Script exited unsuccessfully with status {exc.code}"

        assert CSV_PATH.exists(), "Executing process_backups.py did not create the CSV"
        expected = get_expected_valid_paths()
        actual = read_csv_entries()
        assert actual == expected, (
            f"Executed script produced incorrect CSV.\nExpected: {expected}\nGot: {actual}"
        )
        assert any(row[0] == dynamic_id for row in actual), (
            "Executed script did not process the verifier's newly added recursive manifest"
        )

        target = CSV_PATH.resolve(strict=False)
        matching = [(src, dst) for src, dst in rename_events if dst == target]
        assert matching, "No atomic rename to processed_manifest.csv was observed while executing the script"
        assert any(src != dst and src.parent == target.parent for src, dst in matching), (
            "The CSV must be written to a distinct temporary file in the same directory before os.replace"
        )

        if old_txt is not None:
            assert TXT_PATH.exists() and TXT_PATH.read_bytes() == old_txt, (
                "The Python processing step must not replace the separately produced valid_ids.txt"
            )
    finally:
        sys.argv = original_argv
        os.chdir(original_cwd)
        try:
            dynamic_manifest.unlink(missing_ok=True)
            dynamic_dir.rmdir()
        except OSError:
            pass

        if old_csv is None:
            CSV_PATH.unlink(missing_ok=True)
        else:
            CSV_PATH.write_bytes(old_csv)
        if old_txt is None:
            TXT_PATH.unlink(missing_ok=True)
        else:
            TXT_PATH.write_bytes(old_txt)
            if old_txt_stat is not None:
                os.utime(TXT_PATH, ns=(old_txt_stat.st_atime_ns, old_txt_stat.st_mtime_ns))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
