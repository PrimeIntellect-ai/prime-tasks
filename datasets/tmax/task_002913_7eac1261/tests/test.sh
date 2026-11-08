#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import posixpath
import stat
import subprocess
import tempfile
import zipfile

import pytest

SOURCE = "/home/user/organize.go"
MANIFEST = "/home/user/manifest.json"
ARCHIVE = "/home/user/organized.zip"
RAW_ROOT = "/app/raw_data"


def derive_frame_count():
    with tempfile.TemporaryDirectory() as td:
        pattern = os.path.join(td, "frame_%06d.png")
        subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-y", "-i", "/app/reference.mp4",
             "-vf", "fps=1", pattern],
            check=True,
            timeout=120,
        )
        return len([n for n in os.listdir(td) if n.startswith("frame_") and n.endswith(".png")])


def collect_expected(header_length):
    records = {}
    expected_manifest = {}
    for root, dirs, files in os.walk(RAW_ROOT):
        dirs.sort()
        files.sort()
        for name in files:
            path = os.path.abspath(os.path.join(root, name))
            rel = os.path.relpath(path, RAW_ROOT).replace(os.sep, "/")
            digest = hashlib.sha256()
            size = 0
            header = b""
            with open(path, "rb") as f:
                while True:
                    chunk = f.read(1024 * 1024)
                    if not chunk:
                        break
                    if len(header) < header_length:
                        header += chunk[:header_length - len(header)]
                    digest.update(chunk)
                    size += len(chunk)
            header_hex = header.hex()
            records[rel] = {
                "path": path,
                "hash": digest.hexdigest(),
                "size": size,
                "header": header_hex,
            }
            expected_manifest.setdefault(header_hex, []).append(path)
    for paths in expected_manifest.values():
        paths.sort()
    return records, expected_manifest


def check_go_concurrency_source():
    analyzer = r'''
package main
import (
    "fmt"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "strconv"
)
func main() {
    if len(os.Args) != 2 { os.Exit(2) }
    fs := token.NewFileSet()
    f, err := parser.ParseFile(fs, os.Args[1], nil, 0)
    if err != nil { fmt.Fprintln(os.Stderr, err); os.Exit(1) }
    syncNames := map[string]bool{}
    hasSync := false
    for _, im := range f.Imports {
        p, _ := strconv.Unquote(im.Path.Value)
        if p == "sync" {
            hasSync = true
            name := "sync"
            if im.Name != nil { name = im.Name.Name }
            syncNames[name] = true
        }
    }
    hasGo, hasMutex, hasLock, hasUnlock, hasFlock := false, false, false, false, false
    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.GoStmt:
            hasGo = true
        case *ast.SelectorExpr:
            if id, ok := x.X.(*ast.Ident); ok && syncNames[id.Name] && (x.Sel.Name == "Mutex" || x.Sel.Name == "RWMutex") {
                hasMutex = true
            }
            if x.Sel.Name == "Lock" || x.Sel.Name == "RLock" { hasLock = true }
            if x.Sel.Name == "Unlock" || x.Sel.Name == "RUnlock" { hasUnlock = true }
            if x.Sel.Name == "Flock" { hasFlock = true }
        case *ast.Ident:
            if hasSync && (x.Name == "Mutex" || x.Name == "RWMutex") { hasMutex = true }
        }
        return true
    })
    if !hasGo || !((hasMutex && hasLock && hasUnlock) || hasFlock) {
        fmt.Fprintf(os.Stderr, "goroutine=%v mutex=%v lock=%v unlock=%v flock=%v\n", hasGo, hasMutex, hasLock, hasUnlock, hasFlock)
        os.Exit(1)
    }
}
'''
    analyzer_path = "/tmp/check_go_ast.go"
    binary_path = "/tmp/check_go_ast"
    with open(analyzer_path, "w") as f:
        f.write(analyzer)
    subprocess.run(["go", "build", "-o", binary_path, analyzer_path], check=True, timeout=120)
    subprocess.run([binary_path, SOURCE], check=True, timeout=30)


@pytest.fixture(scope="session")
def generated_outputs():
    assert os.path.isfile(SOURCE), f"Missing Go source file: {SOURCE}"
    assert not os.path.islink(SOURCE), "Go source must be a regular file, not a symlink"

    frame_count = derive_frame_count()
    assert frame_count == 16, f"Expected 16 frames at 1 fps, got {frame_count}"
    records, expected_manifest = collect_expected(frame_count)
    assert len(records) == 2000, f"Expected 2000 input files, found {len(records)}"

    check_go_concurrency_source()

    for output in (MANIFEST, ARCHIVE):
        try:
            os.remove(output)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ["go", "run", SOURCE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=240,
    )
    assert result.returncode == 0, (
        f"Go program failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return frame_count, records, expected_manifest


def test_go_file_exists(generated_outputs):
    assert os.path.isfile(SOURCE), f"Missing Go source file: {SOURCE}"


def test_manifest_exists_and_format(generated_outputs):
    frame_count, records, expected_manifest = generated_outputs
    assert os.path.isfile(MANIFEST), f"Missing manifest file: {MANIFEST}"

    try:
        with open(MANIFEST, "r") as f:
            manifest = json.load(f)
    except json.JSONDecodeError:
        pytest.fail("manifest.json is not valid JSON.")

    assert isinstance(manifest, dict), "Manifest must be a JSON object (dictionary)."

    expected_headers = [
        b'HEADER_A_1234567'.hex(),
        b'HEADER_B_9876543'.hex(),
        b'HEADER_C_0000000'.hex(),
    ]
    assert frame_count == 16
    assert set(manifest) == set(expected_manifest), "Manifest does not contain exactly all observed headers"
    assert set(manifest) == set(expected_headers), "Manifest must contain all three expected headers"

    seen = []
    for key, files in manifest.items():
        assert isinstance(key, str), "Keys in manifest must be strings."
        assert len(key) == 32, f"Key {key} is not a 16-byte hex string (32 chars)."
        assert key in expected_headers, f"Unexpected header hex key in manifest: {key}"
        assert isinstance(files, list), f"Value for key {key} must be an array of paths."
        assert len(files) == len(set(files)), f"Header {key} contains duplicate paths"
        for file_path in files:
            assert isinstance(file_path, str), "Manifest paths must be strings"
            assert file_path.startswith("/app/raw_data/"), f"File path {file_path} is not an absolute path in /app/raw_data/"
            assert os.path.isabs(file_path), f"File path {file_path} is not absolute."
        assert sorted(files) == expected_manifest[key], f"Incorrect path list for header {key}"
        seen.extend(files)

    assert len(seen) == 2000, "Manifest must list all 2000 files exactly once"
    assert len(set(seen)) == 2000, "Manifest contains duplicate file paths"


def archive_name_to_rel(name):
    assert isinstance(name, str) and name, "ZIP entry has an empty name"
    name = name.replace("\\", "/")
    stripped = name.lstrip("/")
    if stripped.startswith("app/raw_data/"):
        stripped = stripped[len("app/raw_data/"):]
    normalized = posixpath.normpath(stripped)
    assert normalized not in ("", ".", ".."), f"Invalid ZIP entry name: {name}"
    assert not normalized.startswith("../"), f"ZIP entry escapes raw_data: {name}"
    return normalized


def link_target_to_rel(entry_rel, target):
    target = target.replace("\\", "/")
    if target.startswith("/app/raw_data/"):
        return posixpath.normpath(target[len("/app/raw_data/"):])
    stripped = target.lstrip("/")
    if stripped.startswith("app/raw_data/"):
        return posixpath.normpath(stripped[len("app/raw_data/"):])
    direct = posixpath.normpath(stripped)
    relative = posixpath.normpath(posixpath.join(posixpath.dirname(entry_rel), target))
    return direct, relative


def test_zip_exists_contents_deduplication_and_size(generated_outputs):
    _, records, _ = generated_outputs
    assert os.path.isfile(ARCHIVE), f"Missing ZIP archive: {ARCHIVE}"

    size = os.path.getsize(ARCHIVE)
    threshold = 2500000
    assert size <= threshold, f"ZIP archive size metric failed: {size} bytes > {threshold} bytes. Deduplication likely failed or was inefficient."

    try:
        with zipfile.ZipFile(ARCHIVE, "r") as z:
            infos = z.infolist()
            assert infos, "ZIP archive must not be empty"
            assert len(infos) == 2000, "ZIP archive must contain one logical entry for each input file"
            assert len({i.filename for i in infos}) == len(infos), "ZIP contains duplicate entry names"

            bad_file = z.testzip()
            assert bad_file is None, f"ZIP archive is corrupted. First bad file: {bad_file}"

            by_rel = {}
            order = {}
            for index, info in enumerate(infos):
                assert not info.is_dir(), f"Unexpected directory entry: {info.filename}"
                rel = archive_name_to_rel(info.filename)
                assert rel in records, f"Unexpected ZIP entry: {info.filename}"
                assert rel not in by_rel, f"Multiple ZIP entries represent {rel}"
                by_rel[rel] = info
                order[rel] = index
            assert set(by_rel) == set(records), "ZIP does not represent exactly all input files"

            regular_by_hash = {}
            symlinks = []
            for rel, info in by_rel.items():
                mode = (info.external_attr >> 16) & 0xFFFF
                if stat.S_ISLNK(mode):
                    symlinks.append((rel, info))
                else:
                    assert info.file_size == records[rel]["size"], f"Wrong size for regular entry {rel}"
                    data = z.read(info)
                    digest = hashlib.sha256(data).hexdigest()
                    assert digest == records[rel]["hash"], f"Wrong contents for regular entry {rel}"
                    regular_by_hash.setdefault(digest, []).append(rel)

            expected_hashes = {r["hash"] for r in records.values()}
            assert set(regular_by_hash) == expected_hashes, "Every unique full SHA-256 value must have one physical ZIP entry"
            for digest, paths in regular_by_hash.items():
                assert len(paths) == 1, f"Checksum {digest} was physically stored {len(paths)} times"

            for rel, info in symlinks:
                raw_target = z.read(info)
                try:
                    target = raw_target.decode("utf-8")
                except UnicodeDecodeError:
                    pytest.fail(f"Symlink target for {rel} is not UTF-8 text")
                candidates = link_target_to_rel(rel, target)
                if isinstance(candidates, str):
                    candidates = (candidates,)
                target_rel = next((c for c in candidates if c in by_rel), None)
                assert target_rel is not None, f"Symlink {rel} points to missing target {target!r}"
                target_info = by_rel[target_rel]
                target_mode = (target_info.external_attr >> 16) & 0xFFFF
                assert not stat.S_ISLNK(target_mode), f"Symlink {rel} must point directly to the physical entry"
                assert records[target_rel]["hash"] == records[rel]["hash"], f"Symlink {rel} points to different file contents"
                assert order[target_rel] < order[rel], f"Symlink {rel} does not point to the first included physical file"

            assert len(symlinks) == len(records) - len(expected_hashes), "All duplicate checksums must be represented as symbolic links"
    except zipfile.BadZipFile:
        pytest.fail("organized.zip is not a valid ZIP file.")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
