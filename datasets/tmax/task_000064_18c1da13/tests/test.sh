#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/port_analyzer.sh"
VIDEO_PATH = "/app/attack_capture.mp4"
CI_PATH = "/home/user/.gitlab-ci.yml"


def frame_truth(path):
    result = subprocess.run(
        ["/usr/bin/ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "frame=pkt_size",
         "-of", "default=noprint_wrappers=1:nokey=1", path],
        capture_output=True, text=True, check=True,
    )
    sizes = [int(line.strip()) for line in result.stdout.splitlines()
             if line.strip().isdigit()]
    assert sizes, f"Oracle could not extract frame sizes from {path}"
    return max(range(len(sizes)), key=lambda i: sizes[i])


def run_script(remove_ci=True):
    if remove_ci and os.path.exists(CI_PATH):
        os.unlink(CI_PATH)
    return subprocess.run(["bash", SCRIPT_PATH], capture_output=True, text=True)


def assert_valid_output(result, truth):
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}. Stderr: {result.stderr}"
    )
    assert re.fullmatch(r"[0-9]+\n", result.stdout), (
        f"Output must contain only one integer followed by a newline; got {result.stdout!r}. "
        f"Stderr: {result.stderr}"
    )
    try:
        predicted = int(result.stdout.strip())
    except ValueError:
        pytest.fail(f"Output is not a valid integer: '{result.stdout.strip()}'. Stderr: {result.stderr}")
    error = abs(truth - predicted)
    assert error <= 2, (
        f"Metric threshold failed: Error {error} > 2. "
        f"Predicted frame {predicted}, expected around {truth}."
    )


@pytest.fixture(scope="session", autouse=True)
def initial_execution():
    truth = frame_truth(VIDEO_PATH)
    result = run_script(remove_ci=True)
    return result, truth


def test_script_exists_and_executable():
    """Test that the port_analyzer.sh script exists and is executable."""
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"


def test_script_output(initial_execution):
    """Execute the script and compare its output with independently derived frame data."""
    result, truth = initial_execution
    assert_valid_output(result, truth)


def test_gitlab_ci_generated(initial_execution):
    """Validate that execution generated the required single-job GitLab pipeline."""
    assert os.path.isfile(CI_PATH), f"CI config missing at {CI_PATH}"
    with open(CI_PATH, "r", encoding="utf-8") as f:
        content = f.read()
    lower = content.lower()

    # Preserve the original component assertions.
    assert "alpine" in lower, "alpine image not found in .gitlab-ci.yml"
    assert "ffmpeg" in lower, "ffmpeg not found in .gitlab-ci.yml"
    assert "bash" in lower, "bash not found in .gitlab-ci.yml"

    assert re.search(r"(?mi)^\s*image\s*:\s*['\"]?alpine:latest['\"]?\s*$", content), (
        "The pipeline must use the alpine:latest image"
    )

    top_keys = []
    for line in content.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = re.match(r"^(['\"]?)([A-Za-z0-9_.-]+)\1\s*:\s*(?:#.*)?$", line)
        if match:
            top_keys.append(match.group(2))

    reserved = {
        "image", "stages", "variables", "default", "workflow", "include",
        "before_script", "after_script", "services", "cache", "pages",
    }
    jobs = [key for key in top_keys if key not in reserved and not key.startswith(".")]
    assert jobs == ["analyze"], f"Expected exactly one job named analyze; found {jobs}"

    analyze_match = re.search(
        r"(?ms)^(['\"]?)analyze\1\s*:\s*\n(.*?)(?=^[^ \t\r\n#][^:\r\n]*:\s*(?:#.*)?$|\Z)",
        content,
    )
    assert analyze_match, "Top-level analyze job is missing"
    body = analyze_match.group(2)
    assert re.search(r"(?m)^\s+script\s*:", body), "analyze job has no script section"

    install_lines = [line.lower() for line in body.splitlines() if "apk" in line.lower() and "add" in line.lower()]
    assert any("ffmpeg" in line and "bash" in line for line in install_lines), (
        "analyze job must install both ffmpeg and bash with apk add"
    )
    command_lines = [line.lower() for line in body.splitlines() if "port_analyzer.sh" in line.lower()]
    assert any("bash" in line or line.strip().lstrip("-").strip().startswith("/home/user/port_analyzer.sh")
               for line in command_lines), (
        "analyze job must execute /home/user/port_analyzer.sh"
    )


def make_dynamic_video(path, spike):
    subprocess.run(
        ["/usr/bin/ffmpeg", "-y", "-loglevel", "error",
         "-f", "lavfi", "-i", "color=c=black:s=320x240:r=30",
         "-f", "lavfi", "-i", "mandelbrot=s=320x240",
         "-filter_complex", f"[0:v][1:v]overlay=enable='eq(n,{spike})'",
         "-t", "8", "-c:v", "libx264", "-crf", "18", path],
        check=True,
    )


def test_analysis_is_not_fixed_to_original_video():
    """Exercise the analyzer on two newly generated captures with different maxima."""
    backup = VIDEO_PATH + ".verifier-backup"
    os.replace(VIDEO_PATH, backup)
    try:
        spikes = [secrets.randbelow(46) + 45, secrets.randbelow(56) + 155]
        for spike in spikes:
            make_dynamic_video(VIDEO_PATH, spike)
            truth = frame_truth(VIDEO_PATH)
            assert abs(truth - spike) <= 2, (
                f"Generated validation video did not place its maximum near frame {spike}"
            )
            result = run_script(remove_ci=True)
            assert_valid_output(result, truth)
            assert os.path.isfile(CI_PATH), "Script did not generate .gitlab-ci.yml when executed"
    finally:
        if os.path.exists(VIDEO_PATH):
            os.unlink(VIDEO_PATH)
        os.replace(backup, VIDEO_PATH)


def test_rejects_old_ffmpeg_version():
    """An otherwise functional ffmpeg/ffprobe reporting 4.1.9 must be rejected with code 1."""
    replaced = []
    try:
        for name in ("ffprobe", "ffmpeg"):
            path = f"/usr/bin/{name}"
            real = f"/usr/bin/{name}.verifier-real"
            os.replace(path, real)
            wrapper = f'''#!/bin/bash
for arg in "$@"; do
    if [[ "$arg" == "-version" || "$arg" == "--version" ]]; then
        echo "{name} version 4.1.9 Copyright verifier"
        exit 0
    fi
done
exec "{real}" "$@"
'''
            with open(path, "w", encoding="utf-8") as f:
                f.write(wrapper)
            os.chmod(path, 0o755)
            replaced.append((path, real))

        result = subprocess.run(["bash", SCRIPT_PATH], capture_output=True, text=True)
        assert result.returncode == 1, (
            f"Script must exit with code 1 for ffmpeg/ffprobe 4.1.9; got {result.returncode}. "
            f"Stdout: {result.stdout!r}, stderr: {result.stderr!r}"
        )
    finally:
        for path, real in reversed(replaced):
            if os.path.exists(path):
                os.unlink(path)
            if os.path.exists(real):
                os.replace(real, path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
