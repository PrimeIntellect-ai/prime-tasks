#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'GO_EOF' > /tmp/inspect_curator_source.go
package main

import (
    "encoding/json"
    "go/ast"
    "go/parser"
    "go/token"
    "os"
    "path/filepath"
    "strconv"
)

type Result struct {
    HasGoStmt bool `json:"has_go_stmt"`
    HasExecCommand bool `json:"has_exec_command"`
    HasGzipWriter bool `json:"has_gzip_writer"`
    HasFileLock bool `json:"has_file_lock"`
    HasVideoPath bool `json:"has_video_path"`
}

func main() {
    if len(os.Args) != 2 {
        os.Exit(2)
    }
    f, err := parser.ParseFile(token.NewFileSet(), os.Args[1], nil, 0)
    if err != nil {
        os.Exit(2)
    }

    imports := map[string]string{}
    for _, imp := range f.Imports {
        p, err := strconv.Unquote(imp.Path.Value)
        if err != nil {
            continue
        }
        name := filepath.Base(p)
        if imp.Name != nil {
            name = imp.Name.Name
        }
        imports[p] = name
    }

    r := Result{}
    ast.Inspect(f, func(n ast.Node) bool {
        switch x := n.(type) {
        case *ast.GoStmt:
            r.HasGoStmt = true
        case *ast.BasicLit:
            if x.Kind == token.STRING {
                if s, err := strconv.Unquote(x.Value); err == nil && s == "/app/data/raw_footage.mp4" {
                    r.HasVideoPath = true
                }
            }
        case *ast.CallExpr:
            sel, ok := x.Fun.(*ast.SelectorExpr)
            if !ok {
                return true
            }
            id, ok := sel.X.(*ast.Ident)
            if !ok {
                return true
            }
            if id.Name == imports["os/exec"] && (sel.Sel.Name == "Command" || sel.Sel.Name == "CommandContext") {
                r.HasExecCommand = true
            }
            if id.Name == imports["compress/gzip"] && (sel.Sel.Name == "NewWriter" || sel.Sel.Name == "NewWriterLevel") {
                r.HasGzipWriter = true
            }
            if id.Name == imports["syscall"] && (sel.Sel.Name == "Flock" || sel.Sel.Name == "FcntlFlock") {
                r.HasFileLock = true
            }
            if id.Name == imports["golang.org/x/sys/unix"] && (sel.Sel.Name == "Flock" || sel.Sel.Name == "FcntlFlock") {
                r.HasFileLock = true
            }
        }
        return true
    })
    json.NewEncoder(os.Stdout).Encode(r)
}
GO_EOF

go build -o /tmp/inspect_curator_source /tmp/inspect_curator_source.go

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import pytest


def jpeg_dimensions(data):
    assert len(data) >= 4 and data[:2] == b"\xff\xd8", "Decompressed artifact is not a JPEG"
    i = 2
    sof_markers = {
        0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
        0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF,
    }
    while i < len(data):
        while i < len(data) and data[i] != 0xFF:
            i += 1
        while i < len(data) and data[i] == 0xFF:
            i += 1
        if i >= len(data):
            break
        marker = data[i]
        i += 1
        if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
            continue
        assert i + 2 <= len(data), "Truncated JPEG marker"
        segment_len = int.from_bytes(data[i:i+2], "big")
        assert segment_len >= 2 and i + segment_len <= len(data), "Invalid JPEG segment"
        if marker in sof_markers:
            assert segment_len >= 7, "Invalid JPEG SOF segment"
            height = int.from_bytes(data[i+3:i+5], "big")
            width = int.from_bytes(data[i+5:i+7], "big")
            return width, height
        i += segment_len
    pytest.fail("JPEG has no valid frame header")


def test_curator_performance_and_correctness():
    source_file = "/home/user/curator.go"
    assert os.path.exists(source_file), f"Source file {source_file} does not exist"

    required_binary = "/home/user/curator"
    assert os.path.isfile(required_binary), f"Compiled binary missing at {required_binary}"
    assert os.access(required_binary, os.X_OK), f"Compiled binary is not executable: {required_binary}"

    inspection = subprocess.run(
        ["/tmp/inspect_curator_source", source_file],
        check=True, capture_output=True, text=True,
    )
    source_features = json.loads(inspection.stdout)
    assert source_features["has_go_stmt"], "Source must launch processing goroutines"
    assert source_features["has_exec_command"], "Source must invoke ffmpeg through os/exec"
    assert source_features["has_gzip_writer"], "Source must create gzip streams with compress/gzip"
    assert source_features["has_file_lock"], "Source must use explicit file locking for the shared audit log"
    assert source_features["has_video_path"], "Source does not reference /app/data/raw_footage.mp4"

    repo_dir = "/home/user/repo"
    if os.path.exists(repo_dir):
        shutil.rmtree(repo_dir)
    os.makedirs(repo_dir, exist_ok=True)

    binary_path = "/tmp/curator"
    compile_cmd = ["go", "build", "-o", binary_path, source_file]
    try:
        subprocess.run(compile_cmd, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to compile Go program:\n{e.stderr}")

    start_time = time.time()
    try:
        subprocess.run([binary_path], check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Execution of compiled binary failed:\n{e.stderr}")
    runtime_seconds = time.time() - start_time
    assert runtime_seconds <= 3.0, f"Execution time {runtime_seconds:.2f}s exceeded the 3.0s threshold"

    manifest_path = os.path.join(repo_dir, "manifest.json")
    assert os.path.exists(manifest_path), f"Manifest file missing at {manifest_path}"
    with open(manifest_path, "r") as f:
        try:
            manifest = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("manifest.json is not valid JSON")

    assert "total_frames" in manifest, "total_frames missing in manifest"
    assert manifest["total_frames"] == 150, f"Expected total_frames to be 150, got {manifest['total_frames']}"
    assert "artifacts" in manifest, "artifacts array missing in manifest"
    assert len(manifest["artifacts"]) == 150, f"Expected 150 artifacts, got {len(manifest['artifacts'])}"

    audit_path = os.path.join(repo_dir, "audit.log")
    assert os.path.exists(audit_path), f"Audit log missing at {audit_path}"
    with open(audit_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 600, f"Expected 600 non-empty lines in audit.log, got {len(lines)}. Interleaved or missing entries?"

    frame_numbers = set()
    audit_order = []
    audit_sizes = {}
    for i in range(0, len(lines), 4):
        begin_line = lines[i]
        size_line = lines[i+1]
        status_line = lines[i+2]
        end_line = lines[i+3]

        begin_match = re.match(r"^BEGIN FRAME (\d+)$", begin_line)
        assert begin_match, f"Invalid BEGIN FRAME line at line {i+1}: {begin_line}"
        frame_number = int(begin_match.group(1))
        frame_numbers.add(frame_number)
        audit_order.append(frame_number)

        size_match = re.match(r"^SIZE: (\d+)$", size_line)
        assert size_match, f"Invalid SIZE line at line {i+2}: {size_line}"
        audit_sizes[frame_number] = int(size_match.group(1))
        assert status_line == "STATUS: PROCESSED", f"Invalid STATUS line at line {i+3}: {status_line}"
        assert end_line == "END FRAME", f"Invalid END FRAME line at line {i+4}: {end_line}"

    assert len(frame_numbers) == 150, f"Expected 150 unique frames in audit.log, found {len(frame_numbers)}"
    assert frame_numbers == set(range(1, 151)), "audit.log must contain frames 1 through 150 exactly once"

    gz_paths = sorted(
        os.path.join(repo_dir, name)
        for name in os.listdir(repo_dir)
        if name.endswith(".gz") and os.path.isfile(os.path.join(repo_dir, name))
    )
    assert len(gz_paths) == 150, f"Expected exactly 150 .gz artifacts, found {len(gz_paths)}"

    files_by_hash = {}
    for path in gz_paths:
        with open(path, "rb") as f:
            payload = f.read()
        digest = hashlib.sha256(payload).hexdigest()
        files_by_hash.setdefault(digest, []).append((path, len(payload)))

    manifest_order = []
    frame_to_path = {}
    used_paths = set()
    for index, artifact in enumerate(manifest["artifacts"]):
        assert isinstance(artifact, dict), f"Manifest artifact {index} is not an object"
        assert set(("frame", "sha256", "size")).issubset(artifact), f"Manifest artifact {index} is missing fields"
        frame = artifact["frame"]
        size = artifact["size"]
        digest = artifact["sha256"]
        assert isinstance(frame, int) and not isinstance(frame, bool), f"Invalid frame in artifact {index}"
        assert isinstance(size, int) and not isinstance(size, bool) and size > 0, f"Invalid size for frame {frame}"
        assert isinstance(digest, str) and re.fullmatch(r"[0-9a-fA-F]{64}", digest), f"Invalid SHA256 for frame {frame}"
        digest = digest.lower()
        manifest_order.append(frame)
        candidates = [entry for entry in files_by_hash.get(digest, []) if entry[0] not in used_paths and entry[1] == size]
        assert candidates, f"No .gz artifact matches manifest hash and size for frame {frame}"
        path, actual_size = candidates[0]
        used_paths.add(path)
        frame_to_path[frame] = path
        assert audit_sizes.get(frame) == actual_size, f"Audit size does not match artifact size for frame {frame}"

    assert set(manifest_order) == set(range(1, 151)), "Manifest must contain frames 1 through 150 exactly once"
    assert len(set(manifest_order)) == 150, "Manifest contains duplicate frame numbers"
    assert manifest_order == audit_order, "Manifest artifact order does not reconstruct the audit log order"
    assert len(used_paths) == 150, "Every .gz artifact must be represented exactly once in the manifest"

    with tempfile.TemporaryDirectory(prefix="curator_frames_") as frames_dir:
        for frame in range(1, 151):
            path = frame_to_path[frame]
            try:
                with gzip.open(path, "rb") as f:
                    jpeg = f.read(10 * 1024 * 1024 + 1)
            except (OSError, EOFError) as e:
                pytest.fail(f"Artifact for frame {frame} is not a valid gzip stream: {e}")
            assert len(jpeg) <= 10 * 1024 * 1024, f"Decompressed artifact for frame {frame} is unreasonably large"
            assert jpeg_dimensions(jpeg) == (640, 360), f"Frame {frame} is not a 640x360 JPEG"
            output_path = os.path.join(frames_dir, f"frame_{frame:03d}.jpg")
            with open(output_path, "wb") as f:
                f.write(jpeg)

        stats_path = os.path.join(frames_dir, "ssim.log")
        filter_arg = f"[0:v][1:v]ssim=stats_file={stats_path}[v]"
        compare_cmd = [
            "ffmpeg", "-v", "error",
            "-framerate", "30", "-start_number", "1", "-i", os.path.join(frames_dir, "frame_%03d.jpg"),
            "-i", "/app/data/raw_footage.mp4",
            "-filter_complex", filter_arg,
            "-map", "[v]", "-frames:v", "150", "-f", "null", "-",
        ]
        try:
            subprocess.run(compare_cmd, check=True, capture_output=True, text=True, timeout=30)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
            pytest.fail(f"Could not compare artifacts with source video: {e}")

        with open(stats_path, "r") as f:
            stat_lines = [line.strip() for line in f if line.strip()]
        assert len(stat_lines) == 150, f"Expected content comparison for 150 frames, got {len(stat_lines)}"
        for frame, line in enumerate(stat_lines, 1):
            match = re.search(r"\bAll:([0-9.]+)", line)
            assert match, f"Missing SSIM result for frame {frame}"
            score = float(match.group(1))
            assert score >= 0.90, f"Artifact frame {frame} does not match the corresponding source-video frame (SSIM {score:.4f})"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
