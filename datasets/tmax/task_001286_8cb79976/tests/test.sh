#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import uuid


def test_processed_directories_and_files():
    # Check logA.tsv
    logA_path = "/home/user/backups/processed/2024-05-01/logA.tsv"
    assert os.path.isfile(logA_path), f"File {logA_path} does not exist"
    with open(logA_path, "r") as f:
        content_A = f.read().strip()
    expected_A = "101\t2024-05-01\tlogin\n102\t2024-05-01\tlogout"
    assert content_A == expected_A, f"Content mismatch in {logA_path}"

    # Check logB.tsv
    logB_path = "/home/user/backups/processed/2024-05-02/logB.tsv"
    assert os.path.isfile(logB_path), f"File {logB_path} does not exist"
    with open(logB_path, "r") as f:
        content_B = f.read().strip()
    expected_B = "103\t2024-05-02\tupload\n104\t2024-05-02\tdownload"
    assert content_B == expected_B, f"Content mismatch in {logB_path}"

    # Check logD.tsv
    logD_path = "/home/user/backups/processed/2024-04-30/logD.tsv"
    assert os.path.isfile(logD_path), f"File {logD_path} does not exist"
    with open(logD_path, "r") as f:
        content_D = f.read().strip()
    expected_D = "99\t2024-04-30\tregister"
    assert content_D == expected_D, f"Content mismatch in {logD_path}"


def test_hard_links():
    logA_path = "/home/user/backups/processed/2024-05-01/logA.tsv"
    logC_path = "/home/user/backups/processed/2024-05-01/logC.tsv"

    assert os.path.isfile(logA_path), f"File {logA_path} does not exist"
    assert os.path.isfile(logC_path), f"File {logC_path} does not exist"

    inode_A = os.stat(logA_path).st_ino
    inode_C = os.stat(logC_path).st_ino

    assert inode_A == inode_C, f"{logA_path} and {logC_path} are not hardlinked (different inodes)"


def test_symlink_latest():
    symlink_path = "/home/user/backups/latest"
    assert os.path.islink(symlink_path), f"{symlink_path} is not a symbolic link"

    target = os.readlink(symlink_path)
    # The target could be absolute or relative. Let's resolve it.
    resolved_target = os.path.abspath(os.path.join(os.path.dirname(symlink_path), target))

    expected_target = "/home/user/backups/processed/2024-05-02"
    assert resolved_target == expected_target, f"Symlink points to {resolved_target} instead of {expected_target}"


def _remove_outputs():
    processed = Path("/home/user/backups/processed")
    latest = Path("/home/user/backups/latest")
    if processed.exists():
        shutil.rmtree(processed)
    processed.mkdir(parents=True)
    if os.path.lexists(latest):
        if latest.is_dir() and not latest.is_symlink():
            shutil.rmtree(latest)
        else:
            latest.unlink()


def _find_rust_launchers():
    home = Path("/home/user")
    manifests = []
    for root, dirs, files in os.walk(home):
        dirs[:] = [d for d in dirs if d not in {"target", ".cargo", ".rustup", "backups"}]
        if "Cargo.toml" in files:
            manifest = Path(root) / "Cargo.toml"
            if any(Path(root).rglob("*.rs")):
                manifests.append(manifest)

    preferred = Path("/home/user/archive_tool/Cargo.toml")
    manifests = sorted(set(manifests), key=lambda p: (p != preferred, str(p)))
    launchers = [("cargo", p) for p in manifests]

    manifest_dirs = [p.parent for p in manifests]
    for source in sorted(home.rglob("*.rs")):
        if any(part in {"target", ".cargo", ".rustup"} for part in source.parts):
            continue
        if any(source == d or d in source.parents for d in manifest_dirs):
            continue
        launchers.append(("rustc", source))
    return launchers


def test_rust_program_on_changed_inputs():
    raw = Path("/home/user/backups/raw")
    token = uuid.uuid4().hex
    seed = int(token[:8], 16)
    base = datetime.date(2031, 1, 1) + datetime.timedelta(days=seed % 1000)
    older_date = (base - datetime.timedelta(days=37)).isoformat()
    duplicate_date = base.isoformat()
    newest_date = (base + datetime.timedelta(days=61)).isoformat()

    names = {
        "primary": "csv_" + token[:10],
        "duplicate": "json_" + token[10:20],
        "older": "old_" + token[20:26],
        "newest": "new_" + token[26:32],
    }
    duplicate_records = [
        {"id": 200000 + seed % 50000, "date": duplicate_date, "event": "rotate," + token[:12]},
        {"id": 300000 + seed % 50000, "date": duplicate_date, "event": "archive-" + token[12:24]},
    ]
    older_records = [{"id": 400000 + seed % 50000, "date": older_date, "event": "older-" + token[4:16]}]
    newest_records = [{"id": 500000 + seed % 50000, "date": newest_date, "event": "newest-" + token[16:28]}]

    def install_inputs():
        if raw.exists():
            shutil.rmtree(raw)
        raw.mkdir(parents=True)
        with (raw / (names["primary"] + ".csv")).open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["id", "date", "event"])
            writer.writeheader()
            writer.writerows(duplicate_records)
        (raw / (names["duplicate"] + ".json")).write_text(json.dumps(duplicate_records))
        with (raw / (names["older"] + ".csv")).open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["id", "date", "event"])
            writer.writeheader()
            writer.writerows(older_records)
        (raw / (names["newest"] + ".json")).write_text(json.dumps(newest_records))

    def expected_text(records):
        return "\n".join(f'{r["id"]}\t{r["date"]}\t{r["event"]}' for r in records)

    def validate():
        paths = {
            "primary": Path("/home/user/backups/processed") / duplicate_date / (names["primary"] + ".tsv"),
            "duplicate": Path("/home/user/backups/processed") / duplicate_date / (names["duplicate"] + ".tsv"),
            "older": Path("/home/user/backups/processed") / older_date / (names["older"] + ".tsv"),
            "newest": Path("/home/user/backups/processed") / newest_date / (names["newest"] + ".tsv"),
        }
        for path in paths.values():
            assert path.is_file(), f"missing dynamically requested output {path}"
        assert paths["primary"].read_text().rstrip("\n") == expected_text(duplicate_records)
        assert paths["duplicate"].read_text().rstrip("\n") == expected_text(duplicate_records)
        assert paths["older"].read_text().rstrip("\n") == expected_text(older_records)
        assert paths["newest"].read_text().rstrip("\n") == expected_text(newest_records)
        assert os.stat(paths["primary"]).st_ino == os.stat(paths["duplicate"]).st_ino, "identical dynamic outputs are not hard-linked"
        latest = Path("/home/user/backups/latest")
        assert latest.is_symlink(), "latest was not recreated as a symlink"
        resolved = os.path.abspath(os.path.join(str(latest.parent), os.readlink(latest)))
        assert resolved == str(Path("/home/user/backups/processed") / newest_date)

    launchers = _find_rust_launchers()
    assert launchers, "no Rust source program or Cargo project was found"
    failures = []
    for kind, artifact in launchers:
        install_inputs()
        _remove_outputs()
        try:
            if kind == "cargo":
                proc = subprocess.run(
                    ["/usr/bin/cargo", "run", "--quiet", "--manifest-path", str(artifact)],
                    cwd=str(artifact.parent), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, timeout=180
                )
            else:
                binary = Path("/tmp/archive_tool_dynamic_" + uuid.uuid4().hex)
                compile_proc = subprocess.run(
                    ["/usr/bin/rustc", str(artifact), "-o", str(binary)],
                    cwd=str(artifact.parent), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, timeout=120
                )
                if compile_proc.returncode != 0:
                    failures.append(f"{artifact}: compilation failed: {compile_proc.stderr[-500:]}")
                    continue
                proc = subprocess.run(
                    [str(binary)], cwd=str(artifact.parent), stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE, text=True, timeout=120
                )
                binary.unlink(missing_ok=True)
            if proc.returncode != 0:
                failures.append(f"{artifact}: exited {proc.returncode}: {proc.stderr[-500:]}")
                continue
            try:
                validate()
                return
            except AssertionError as exc:
                failures.append(f"{artifact}: {exc}")
        except (subprocess.TimeoutExpired, OSError) as exc:
            failures.append(f"{artifact}: {exc}")

    raise AssertionError("No Rust implementation correctly processed changed inputs. " + " | ".join(failures))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
