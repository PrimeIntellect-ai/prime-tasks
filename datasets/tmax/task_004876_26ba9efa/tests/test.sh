#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import stat
import subprocess
import tempfile
import uuid


def run_pipeline():
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "/home/user/pipeline.sh"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"pipeline.sh failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def valid_cron_line(line):
    line = line.strip()
    if not line or line.startswith("#"):
        return False
    return bool(
        re.search(r'^(\*/15|0,15,30,45)\s+\*\s+\*\s+\*\s+\*', line)
        and "/home/user/pipeline.sh" in line
    )


def test_pipeline_script_exists_and_executable():
    script_path = "/home/user/pipeline.sh"
    assert os.path.isfile(script_path), f"Pipeline script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Pipeline script {script_path} is not executable."

    analyzers = [
        "/home/user/analyze.py",
        "/home/user/analyze.rb",
        "/home/user/analyze.pl",
    ]
    existing = [path for path in analyzers if os.path.isfile(path)]
    assert existing, "No analysis script exists at analyze.py, analyze.rb, or analyze.pl."

    with open(script_path, "r", errors="replace") as f:
        pipeline_text = f.read()
    assert any(os.path.basename(path) in pipeline_text for path in existing), (
        "pipeline.sh does not invoke the submitted analysis script."
    )


def test_processing_data_synced():
    src_dir = "/tmp/remote_drop"
    dest_dir = "/home/user/processing_data"

    assert os.path.isdir(dest_dir), f"Destination directory {dest_dir} does not exist."

    src_files = os.listdir(src_dir)
    assert len(src_files) > 0, f"Source directory {src_dir} is empty."

    for f in src_files:
        src_file = os.path.join(src_dir, f)
        dest_file = os.path.join(dest_dir, f)
        assert os.path.isfile(dest_file), f"File {f} was not synchronized to {dest_dir}."
        with open(src_file, "rb") as src, open(dest_file, "rb") as dest:
            assert dest.read() == src.read(), f"Contents of synchronized file {f} differ from the source."


def test_latest_match_log():
    log_path = "/home/user/latest_match.log"
    assert os.path.isfile(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip()

    assert content == "doc3.txt,0.6154", f"Expected 'doc3.txt,0.6154' in {log_path}, but got '{content}'."


def test_crontab_dump_and_installed_crontab():
    dump_path = "/home/user/crontab_dump.txt"
    assert os.path.isfile(dump_path), f"Crontab dump file {dump_path} does not exist."

    with open(dump_path, "r") as f:
        dump_content = f.read()

    assert any(valid_cron_line(line) for line in dump_content.splitlines()), (
        f"Could not find a valid cron job for running /home/user/pipeline.sh every 15 minutes in {dump_path}."
    )

    installed = subprocess.run(
        ["crontab", "-u", "user", "-l"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert installed.returncode == 0, f"No crontab is installed for user: {installed.stderr.strip()}"
    assert dump_content == installed.stdout, (
        "crontab_dump.txt is not an actual dump of the installed user crontab."
    )
    assert any(valid_cron_line(line) for line in installed.stdout.splitlines()), (
        "The installed user crontab does not run /home/user/pipeline.sh every 15 minutes."
    )


def test_pipeline_performs_rsync_and_dynamic_jaccard_workflow():
    remote = "/tmp/remote_drop"
    processing = "/home/user/processing_data"
    target = "/home/user/target_profile.txt"
    log = "/home/user/latest_match.log"
    rsync_path = "/usr/bin/rsync"

    token = uuid.uuid4().hex
    words = ["alpha" + token[:8], "beta" + token[8:16], "gamma" + token[16:24], "n" + token[24:]]
    winner = f"winner_{uuid.uuid4().hex}.txt"
    other1 = f"other_{uuid.uuid4().hex}.txt"
    other2 = f"other_{uuid.uuid4().hex}.txt"

    fixture_backup = tempfile.mkdtemp(prefix="verifier-fixtures-")
    remote_backup = os.path.join(fixture_backup, "remote")
    os.mkdir(remote_backup)
    for name in os.listdir(remote):
        path = os.path.join(remote, name)
        if os.path.isfile(path):
            shutil.copy2(path, os.path.join(remote_backup, name))
    target_backup = os.path.join(fixture_backup, "target_profile.txt")
    shutil.copy2(target, target_backup)

    real_rsync = f"/tmp/real-rsync-{uuid.uuid4().hex}"
    marker = f"/tmp/rsync-marker-{uuid.uuid4().hex}"
    original_mode = stat.S_IMODE(os.stat(rsync_path).st_mode)

    try:
        for name in os.listdir(remote):
            path = os.path.join(remote, name)
            if os.path.isdir(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)
        for name in os.listdir(processing):
            path = os.path.join(processing, name)
            if os.path.isdir(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)

        with open(target, "w") as f:
            f.write(f"{words[0]}, {words[1]} {words[1]}! {words[2].upper()} {words[3]}.\n")
        documents = {
            winner: f"{words[3]}--{words[2]} {words[1].upper()}, {words[0]} {words[0]}\n",
            other1: f"{words[0]} {words[1]} unrelated extra\n",
            other2: "completely unrelated document words\n",
        }
        for name, content in documents.items():
            with open(os.path.join(remote, name), "w") as f:
                f.write(content)

        with open(marker, "w"):
            pass
        os.chmod(marker, 0o666)
        os.rename(rsync_path, real_rsync)
        with open(rsync_path, "w") as wrapper:
            wrapper.write("#!/bin/sh\nprintf 'called\\n' >> " + marker + "\nexec " + real_rsync + " \"$@\"\n")
        os.chmod(rsync_path, 0o755)

        run_pipeline()

        with open(marker, "r") as f:
            assert f.read().strip(), "pipeline.sh did not invoke rsync."

        for name, expected_content in documents.items():
            destination = os.path.join(processing, name)
            assert os.path.isfile(destination), f"Dynamic source file {name} was not synchronized."
            with open(destination, "r") as f:
                assert f.read() == expected_content, f"rsync did not preserve the contents of {name}."

        assert os.path.isfile(log), "pipeline.sh did not create latest_match.log."
        with open(log, "r") as f:
            result = f.read().strip()
        assert result == f"{winner},1.0000", (
            f"Dynamic Jaccard result was incorrect: expected {winner},1.0000 but got {result!r}."
        )
    finally:
        if os.path.exists(real_rsync):
            os.replace(real_rsync, rsync_path)
            os.chmod(rsync_path, original_mode)
        if os.path.exists(marker):
            os.unlink(marker)

        for name in os.listdir(remote):
            path = os.path.join(remote, name)
            if os.path.isdir(path):
                shutil.rmtree(path)
            else:
                os.unlink(path)
        for name in os.listdir(remote_backup):
            shutil.copy2(os.path.join(remote_backup, name), os.path.join(remote, name))
        shutil.copy2(target_backup, target)
        shutil.rmtree(fixture_backup)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
