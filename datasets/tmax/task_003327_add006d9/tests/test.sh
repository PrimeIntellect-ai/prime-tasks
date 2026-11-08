#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tempfile
from pathlib import Path

HOME = Path("/home/user")
INCOMING = Path("/app/incoming_alerts")


def run_pipeline():
    result = subprocess.run(
        [str(HOME / "pipeline.sh")],
        cwd=str(HOME),
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"pipeline.sh failed with exit {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_00_execute_pipeline_from_clean_outputs():
    pipeline_file = HOME / "pipeline.sh"
    extract_file = HOME / "extract_alerts.sh"
    filter_file = HOME / "alert_filter.sh"

    for script in (pipeline_file, extract_file, filter_file):
        assert script.is_file(), f"Missing script: {script}"
        assert os.access(script, os.X_OK), f"Script is not executable: {script}"

    shutil.rmtree(HOME / "dashboard_frames", ignore_errors=True)
    shutil.rmtree(HOME / "verified_maildir", ignore_errors=True)
    (HOME / "frame_count.txt").unlink(missing_ok=True)
    run_pipeline()


def test_frame_count():
    frame_count_file = Path("/home/user/frame_count.txt")
    assert frame_count_file.is_file(), f"Missing frame count file: {frame_count_file}"
    content = frame_count_file.read_text().strip()
    assert content == "12", f"Expected frame count to be '12', but got '{content}'."

    frames_dir = HOME / "dashboard_frames"
    assert frames_dir.is_dir(), f"Missing extracted frame directory: {frames_dir}"
    submitted = [p for p in frames_dir.iterdir() if p.is_file()]

    def natural_key(path):
        return [int(x) if x.isdigit() else x for x in re.split(r"(\d+)", path.name)]

    submitted.sort(key=natural_key)
    with tempfile.TemporaryDirectory() as td:
        reference_dir = Path(td)
        reference_pattern = reference_dir / "frame_%06d.png"
        result = subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i",
             "/app/dashboard_capture.mp4", "-vf", "fps=1", str(reference_pattern)],
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert result.returncode == 0, f"Could not derive reference frames: {result.stderr}"
        reference = sorted(reference_dir.glob("frame_*.png"), key=natural_key)
        assert int(content) == len(reference), (
            f"frame_count.txt says {content}, but ffmpeg extracts {len(reference)} frames"
        )
        assert len(submitted) == len(reference), (
            f"Expected {len(reference)} extracted frame files, found {len(submitted)}"
        )

        for actual, expected in zip(submitted, reference):
            identify = subprocess.run(
                ["identify", "-format", "%w %h", str(actual)],
                capture_output=True,
                text=True,
            )
            assert identify.returncode == 0, f"Not a valid image frame: {actual}"
            assert identify.stdout == "640 480", f"Wrong frame dimensions for {actual}: {identify.stdout}"

            comparison = subprocess.run(
                ["compare", "-metric", "RMSE", str(actual), str(expected), "null:"],
                capture_output=True,
                text=True,
            )
            assert comparison.returncode in (0, 1), f"Could not compare frame {actual}: {comparison.stderr}"
            match = re.search(r"\(([-+0-9.eE]+)\)", comparison.stderr)
            assert match, f"Could not read comparison metric for {actual}: {comparison.stderr}"
            assert float(match.group(1)) <= 0.03, f"Extracted frame {actual} does not match the video"


def test_alert_routes():
    routes_file = Path("/home/user/alert_routes.conf")
    assert routes_file.is_file(), f"Missing routes config file: {routes_file}"
    lines = [line.strip() for line in routes_file.read_text().strip().splitlines() if line.strip()]
    expected_lines = [
        "10.50.0.0/16 via 192.168.1.254",
        "0.0.0.0/0 via 192.168.1.1"
    ]
    assert lines == expected_lines, f"Routes config does not match expected. Got: {lines}"


def test_pipeline_exists_executable():
    pipeline_file = Path("/home/user/pipeline.sh")
    assert pipeline_file.is_file(), f"Missing pipeline script: {pipeline_file}"
    assert os.access(pipeline_file, os.X_OK), f"Pipeline script is not executable: {pipeline_file}"


def test_verified_maildir():
    maildir = Path("/home/user/verified_maildir/new")
    assert maildir.is_dir(), f"Missing verified maildir: {maildir}"

    files = list(maildir.iterdir())
    assert len(files) == 1, f"Expected exactly 1 file in {maildir}, found {len(files)}"

    clean_eml_path = maildir / "clean1.eml"
    assert clean_eml_path.is_file(), f"Expected clean1.eml in {maildir}"
    file_content = clean_eml_path.read_text().strip()
    expected_content = Path("/app/incoming_alerts/clean1.eml").read_text().strip()
    assert file_content == expected_content, f"File in maildir does not match clean1.eml content. Got: {file_content}"


def test_alert_filter_eval_corpus():
    filter_script = Path("/home/user/alert_filter.sh")
    assert filter_script.is_file(), f"Missing alert filter script: {filter_script}"
    assert os.access(filter_script, os.X_OK), f"Alert filter script is not executable: {filter_script}"

    clean_corpus_dir = Path("/app/eval_corpora/clean_alerts")
    evil_corpus_dir = Path("/app/eval_corpora/evil_alerts")

    clean_modified = []
    for clean_file in clean_corpus_dir.iterdir():
        if clean_file.is_file():
            result = subprocess.run([str(filter_script), str(clean_file)], capture_output=True)
            if result.returncode != 0:
                clean_modified.append(clean_file.name)

    evil_bypassed = []
    for evil_file in evil_corpus_dir.iterdir():
        if evil_file.is_file():
            result = subprocess.run([str(filter_script), str(evil_file)], capture_output=True)
            if result.returncode == 0:
                evil_bypassed.append(evil_file.name)

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(list(evil_corpus_dir.iterdir()))} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(list(clean_corpus_dir.iterdir()))} clean modified/rejected: {', '.join(clean_modified)}")

    assert not errors, "Adversarial corpus verification failed:\n" + "\n".join(errors)


def test_dynamic_filter_and_pipeline_behavior():
    token = secrets.token_hex(12)
    filter_script = HOME / "alert_filter.sh"
    samples = {
        f"clean-{token}.eml": (f"Alert {token}: latency 42 ms JSON {{\"value\": 42}}\n", True),
        f"clean-extra-{token}.eml": (f"Service {token} recovered successfully.\n", True),
        f"evil-dollar-{token}.eml": (f"Alert {token}: $(printf injected)\n", False),
        f"evil-tick-{token}.eml": (f"Alert {token}: `printf injected`\n", False),
        f"evil-sql-{token}.eml": (f"Metric {token}: DROP TABLE alerts;\n", False),
    }

    with tempfile.TemporaryDirectory() as td:
        sample_dir = Path(td)
        for name, (content, should_pass) in samples.items():
            path = sample_dir / name
            path.write_text(content)
            result = subprocess.run([str(filter_script), str(path)], capture_output=True)
            assert (result.returncode == 0) == should_pass, (
                f"Filter classified dynamic sample {name} incorrectly; exit={result.returncode}"
            )

    with tempfile.TemporaryDirectory() as backup_td:
        backup = Path(backup_td) / "incoming_alerts"
        shutil.copytree(INCOMING, backup)
        try:
            shutil.rmtree(INCOMING)
            INCOMING.mkdir()
            for name, (content, _) in samples.items():
                (INCOMING / name).write_text(content)

            shutil.rmtree(HOME / "verified_maildir", ignore_errors=True)
            shutil.rmtree(HOME / "dashboard_frames", ignore_errors=True)
            (HOME / "frame_count.txt").unlink(missing_ok=True)
            run_pipeline()

            output = HOME / "verified_maildir" / "new"
            assert output.is_dir(), f"Pipeline did not create {output}"
            actual_names = {p.name for p in output.iterdir() if p.is_file()}
            expected_names = {name for name, (_, clean) in samples.items() if clean}
            assert actual_names == expected_names, (
                f"Pipeline routed the wrong dynamic messages. Expected {expected_names}, got {actual_names}"
            )
            for name in expected_names:
                assert (output / name).read_bytes() == (INCOMING / name).read_bytes(), (
                    f"Pipeline changed the contents of {name}"
                )
        finally:
            shutil.rmtree(INCOMING, ignore_errors=True)
            shutil.copytree(backup, INCOMING)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
