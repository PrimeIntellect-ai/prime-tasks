#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import shlex
import subprocess
import tempfile
import uuid
from pathlib import Path


def test_perturbations_fixed():
    """Verify that the deliberate perturbations in the vendored package have been fixed."""
    makefile_path = Path("/app/bash-ds-utils/Makefile")
    assert makefile_path.is_file(), "Makefile is missing."
    makefile_content = makefile_path.read_text()
    assert "CC=/usr/bin/false" not in makefile_content, "Makefile still contains the perturbation 'CC=/usr/bin/false'."

    setup_env_path = Path("/app/bash-ds-utils/setup_env.sh")
    assert setup_env_path.is_file(), "setup_env.sh is missing."
    setup_env_content = setup_env_path.read_text()
    assert "TRACKER_HOME=/nonexistent" not in setup_env_content, "setup_env.sh still contains the perturbation 'TRACKER_HOME=/nonexistent'."


def test_track_exp_compiled_and_runs():
    """Verify make install really succeeds and the initialized tracker runs."""
    package = Path("/app/bash-ds-utils")
    build = subprocess.run(
        ["make", "-B", "install"], cwd=package, capture_output=True, text=True
    )
    assert build.returncode == 0, f"make install failed:\n{build.stdout}\n{build.stderr}"

    track_exp = package / "bin/track_exp"
    assert track_exp.is_file(), "track_exp binary was not compiled. Did you run 'make install'?"
    assert os.access(track_exp, os.X_OK), "track_exp binary is not executable."

    with tempfile.TemporaryDirectory(prefix="tracker-init-") as workdir:
        initialized = subprocess.run(
            ["bash", "-c", "source /app/bash-ds-utils/setup_env.sh && /app/bash-ds-utils/bin/track_exp --init"],
            cwd=workdir,
            capture_output=True,
            text=True,
        )
    assert initialized.returncode == 0, (
        f"track_exp --init failed:\n{initialized.stdout}\n{initialized.stderr}"
    )


def test_filter_script_exists():
    """Verify that the filter.sh script exists and is executable."""
    filter_script = Path("/home/user/filter.sh")
    assert filter_script.is_file(), "filter.sh script does not exist at /home/user/filter.sh."
    assert os.access(filter_script, os.X_OK), "filter.sh script is not executable."


def write_constant_dataset(path, rows, cols, value):
    line = "\t".join([f"{value:.12f}"] * cols) + "\n"
    path.write_text(line * rows)


def test_adversarial_corpus_and_generated_inputs_are_logged():
    """Test both the shipped corpus and opaque generated datasets, recording tracker calls."""
    filter_script = Path("/home/user/filter.sh")
    clean_dir = Path("/home/user/data/clean")
    evil_dir = Path("/home/user/data/evil")

    assert clean_dir.is_dir(), f"Clean corpus directory {clean_dir} missing."
    assert evil_dir.is_dir(), f"Evil corpus directory {evil_dir} missing."

    clean_files = list(clean_dir.glob("*"))
    evil_files = list(evil_dir.glob("*"))
    assert len(clean_files) > 0, "No files found in clean corpus."
    assert len(evil_files) > 0, "No files found in evil corpus."

    generated_dir = Path(tempfile.mkdtemp(prefix="vector-eval-"))
    generated = []

    def opaque_path():
        return generated_dir / uuid.uuid4().hex

    clean = opaque_path()
    write_constant_dataset(clean, 137, 50, 0.1 + 10.0 / math.sqrt(50.0))
    generated.append((clean, 0, "clean"))

    high = opaque_path()
    write_constant_dataset(high, 113, 50, 0.1 + 20.0 / math.sqrt(50.0))
    generated.append((high, 1, "evil"))

    low = opaque_path()
    write_constant_dataset(low, 109, 50, 0.1 + 2.0 / math.sqrt(50.0))
    generated.append((low, 1, "evil"))

    wrong49 = opaque_path()
    write_constant_dataset(wrong49, 101, 49, 0.1 + 10.0 / math.sqrt(50.0))
    generated.append((wrong49, 1, "evil"))

    wrong51 = opaque_path()
    write_constant_dataset(wrong51, 103, 51, 0.1 + 10.0 / math.sqrt(50.0))
    generated.append((wrong51, 1, "evil"))

    inconsistent = opaque_path()
    good_line = "\t".join(["1.514213562373"] * 50)
    bad_line = "\t".join(["1.514213562373"] * 49)
    inconsistent.write_text((good_line + "\n") * 60 + bad_line + "\n" + (good_line + "\n") * 60)
    generated.append((inconsistent, 1, "evil"))

    evaluations = [(f, 0, "clean") for f in clean_files]
    evaluations += [(f, 1, "evil") for f in evil_files]
    evaluations += generated
    random.SystemRandom().shuffle(evaluations)

    tracker = Path("/app/bash-ds-utils/bin/track_exp")
    real_tracker = tracker.with_name(".verifier-real-track-exp")
    log_path = Path(tempfile.mkstemp(prefix="track-calls-")[1])
    log_path.write_text("")

    assert tracker.is_file() and os.access(tracker, os.X_OK)
    if real_tracker.exists():
        real_tracker.unlink()
    os.replace(tracker, real_tracker)
    wrapper = """#!/bin/bash
printf '%s\\t' "$@" >> {log}
printf '\\n' >> {log}
exec {real} "$@"
""".format(log=shlex.quote(str(log_path)), real=shlex.quote(str(real_tracker)))
    tracker.write_text(wrapper)
    tracker.chmod(0o755)

    failures = []
    try:
        for path, expected_rc, expected_status in evaluations:
            result = subprocess.run([str(filter_script), str(path)], capture_output=True)
            if result.returncode != expected_rc:
                failures.append(
                    f"{path}: expected exit {expected_rc}, got {result.returncode}"
                )
    finally:
        if tracker.exists():
            tracker.unlink()
        os.replace(real_tracker, tracker)
        for path, _, _ in generated:
            path.unlink(missing_ok=True)
        generated_dir.rmdir()

    assert not failures, " | ".join(failures)

    calls = []
    for line in log_path.read_text().splitlines():
        fields = line.split("\t")
        if fields and fields[-1] == "":
            fields.pop()
        calls.append(fields)
    log_path.unlink(missing_ok=True)

    logging_errors = []
    for path, _, expected_status in evaluations:
        calls_for_path = [
            call for call in calls
            if len(call) >= 2 and call[0] == "--log" and call[1] == str(path)
        ]
        expected_call = ["--log", str(path), "--status", expected_status]
        if calls_for_path != [expected_call]:
            logging_errors.append(
                f"{path}: expected exactly one tracker call {expected_call!r}, got {calls_for_path!r}"
            )
    assert not logging_errors, " | ".join(logging_errors)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
