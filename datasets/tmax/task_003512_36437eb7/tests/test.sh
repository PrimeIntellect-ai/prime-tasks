#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import os
import shutil
import subprocess
import tempfile


def run_checked(args):
    proc = subprocess.run(args, capture_output=True)
    assert proc.returncode == 0, (
        f"Command failed ({proc.returncode}): {' '.join(args)}\n"
        f"stderr: {proc.stderr.decode('utf-8', errors='ignore')}"
    )
    return proc


def frame_hashes(pattern):
    proc = run_checked([
        "ffmpeg", "-v", "error", "-start_number", "1", "-i", pattern,
        "-an", "-pix_fmt", "rgb24", "-f", "framemd5", "-"
    ])
    hashes = []
    for line in proc.stdout.decode("ascii", errors="strict").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = [part.strip() for part in line.split(",")]
        assert len(parts) >= 6, f"Malformed framemd5 output line: {line}"
        hashes.append(parts[-1])
    assert hashes, f"No decodable frames found for {pattern}"
    return hashes


def test_final_state():
    video_path = "/app/surveillance.mp4"
    archive_path = "/home/user/surveillance.dedup"
    raw_frames_dir = "/home/user/raw_frames"
    unpack_dir = "/home/user/unpacked_frames"
    archiver_src = "/home/user/archiver.c"
    archiver_bin = "/home/user/archiver"

    assert os.path.isfile(video_path), f"Video not found at {video_path}."
    assert os.path.exists(archive_path), f"Archive file not found at {archive_path}."
    assert os.path.isfile(archiver_bin), f"Archiver binary not found at {archiver_bin}."
    assert os.access(archiver_bin, os.X_OK), "Archiver is not executable."
    assert os.path.isfile(archiver_src), f"Archiver C source not found at {archiver_src}."
    with open(archiver_bin, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Archiver is not a compiled ELF executable."
    assert os.path.isdir(raw_frames_dir), f"Raw frames directory not found at {raw_frames_dir}."

    with tempfile.TemporaryDirectory(prefix="verifier_frames_") as work_dir:
        expected_dir = os.path.join(work_dir, "expected")
        os.makedirs(expected_dir)

        # Independently extract every frame from the supplied video. This is the
        # trusted source for frame count, numbering, pixels, and ratio accounting.
        run_checked([
            "ffmpeg", "-v", "error", "-i", video_path,
            os.path.join(expected_dir, "out_%04d.png")
        ])
        expected_files = sorted(
            name for name in os.listdir(expected_dir) if name.endswith(".png")
        )
        assert expected_files, "Independent extraction produced no frames."
        assert expected_files == [
            f"out_{i:04d}.png" for i in range(1, len(expected_files) + 1)
        ], "Independent extraction did not produce a contiguous frame sequence."

        raw_files = sorted(os.listdir(raw_frames_dir))
        assert raw_files, "No raw frames found in raw_frames directory."

        # Preserve and strengthen the required naming check: exactly one
        # contiguous, 1-based cam_A_frame sequence must be present.
        for f in raw_files:
            assert f.startswith("cam_A_frame_") and f.endswith(".png"), (
                f"File {f} does not match the required naming pattern "
                "'cam_A_frame_<N>.png'."
            )
        expected_raw_names = [
            f"cam_A_frame_{i:04d}.png" for i in range(1, len(expected_files) + 1)
        ]
        assert raw_files == expected_raw_names, (
            "raw_frames does not contain exactly the frames extracted from the video "
            "with contiguous 1-based names."
        )

        expected_hashes = frame_hashes(os.path.join(expected_dir, "out_%04d.png"))
        raw_hashes = frame_hashes(os.path.join(raw_frames_dir, "cam_A_frame_%04d.png"))
        assert raw_hashes == expected_hashes, (
            "The PNG frames in raw_frames do not match the decoded frames of "
            "/app/surveillance.mp4."
        )

        # 1. Check Verify command on the submitted archive.
        verify_proc = subprocess.run([archiver_bin, "verify", archive_path], capture_output=True)
        assert verify_proc.returncode == 0, (
            f"Archiver verify command failed with exit code {verify_proc.returncode}. "
            f"stderr: {verify_proc.stderr.decode('utf-8', errors='ignore')}"
        )

        # 2. Unpack the submitted archive.
        if os.path.exists(unpack_dir):
            shutil.rmtree(unpack_dir)
        os.makedirs(unpack_dir, exist_ok=True)

        unpack_proc = subprocess.run(
            [archiver_bin, "unpack", archive_path, unpack_dir], capture_output=True
        )
        assert unpack_proc.returncode == 0, (
            f"Archiver unpack command failed with exit code {unpack_proc.returncode}. "
            f"stderr: {unpack_proc.stderr.decode('utf-8', errors='ignore')}"
        )

        # 3. Preserve the exact raw-to-unpacked comparison.
        unpacked_files = sorted(os.listdir(unpack_dir))
        assert raw_files == unpacked_files, "Unpacked filenames do not match raw frames."

        total_raw_size = 0
        for f in raw_files:
            raw_path = os.path.join(raw_frames_dir, f)
            unp_path = os.path.join(unpack_dir, f)
            assert filecmp.cmp(raw_path, unp_path, shallow=False), f"File content mismatch for {f}"
            total_raw_size += os.path.getsize(raw_path)

        # Exercise pack/unpack independently on verifier-created PNG inputs,
        # including an exact duplicate, rather than trusting only the prebuilt archive.
        probe_input = os.path.join(work_dir, "probe_input")
        probe_snapshot = os.path.join(work_dir, "probe_snapshot")
        probe_output = os.path.join(work_dir, "probe_output")
        probe_archive = os.path.join(work_dir, "probe.dedup")
        os.makedirs(probe_input)
        os.makedirs(probe_snapshot)

        probe_sources = [expected_files[0], expected_files[0]]
        different_index = next(
            (i for i, h in enumerate(expected_hashes) if h != expected_hashes[0]),
            None,
        )
        if different_index is not None:
            probe_sources.append(expected_files[different_index])

        for i, source_name in enumerate(probe_sources, 1):
            target_name = f"probe_{i:04d}.png"
            shutil.copyfile(
                os.path.join(expected_dir, source_name),
                os.path.join(probe_input, target_name),
            )
            shutil.copyfile(
                os.path.join(expected_dir, source_name),
                os.path.join(probe_snapshot, target_name),
            )

        run_checked([archiver_bin, "pack", probe_input, probe_archive])
        run_checked([archiver_bin, "verify", probe_archive])
        shutil.rmtree(probe_input)
        os.makedirs(probe_output)
        run_checked([archiver_bin, "unpack", probe_archive, probe_output])

        probe_names = sorted(os.listdir(probe_snapshot))
        assert sorted(os.listdir(probe_output)) == probe_names, (
            "Independent pack/unpack did not preserve PNG filenames."
        )
        for name in probe_names:
            assert filecmp.cmp(
                os.path.join(probe_snapshot, name),
                os.path.join(probe_output, name),
                shallow=False,
            ), f"Independent pack/unpack changed {name}"

        # 4. Preserve the original metric and additionally use trusted extracted
        # frame sizes so agent-controlled padding cannot manufacture the ratio.
        assert total_raw_size > 0, "Total size of raw frames is 0."
        archive_size = os.path.getsize(archive_path)
        compression_ratio = archive_size / total_raw_size
        assert compression_ratio < 0.25, (
            f"Compression ratio {compression_ratio:.4f} is not strictly less than 0.25."
        )

        trusted_total_size = sum(
            os.path.getsize(os.path.join(expected_dir, name)) for name in expected_files
        )
        assert trusted_total_size > 0, "Trusted extracted frame size is 0."
        trusted_ratio = archive_size / trusted_total_size
        assert trusted_ratio < 0.25, (
            f"Compression ratio against independently extracted frames "
            f"{trusted_ratio:.4f} is not strictly less than 0.25."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
