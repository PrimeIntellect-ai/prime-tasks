#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import tempfile
import shutil
import re
import secrets
import uuid


def test_directories_exist():
    assert os.path.isdir("/home/user/spool"), "Directory /home/user/spool does not exist"
    assert os.path.isdir("/home/user/results"), "Directory /home/user/results does not exist"


def test_git_repo_and_hook():
    repo_dir = "/home/user/backup_repo.git"
    assert os.path.isdir(os.path.join(repo_dir, "objects")), f"Bare git repository not found at {repo_dir}"

    hook_path = os.path.join(repo_dir, "hooks", "post-receive")
    assert os.path.isfile(hook_path), f"post-receive hook not found at {hook_path}"
    assert os.access(hook_path, os.X_OK), f"post-receive hook at {hook_path} is not executable"


def test_verify_restore_program():
    prog_path = "/home/user/verify_restore"
    assert os.path.isfile(prog_path), f"C++ program not found at {prog_path}"
    assert os.access(prog_path, os.X_OK), f"C++ program at {prog_path} is not executable"

    # Test OK case
    p = subprocess.run([prog_path], input=b"file1.dat\nfile2.dat\n", capture_output=True)
    assert p.stdout.decode('utf-8').strip() == "STATUS: OK, COUNT: 2", "verify_restore did not output 'STATUS: OK, COUNT: 2' for valid input"

    # Test ERROR case
    p = subprocess.run([prog_path], input=b"file1.dat\nbadfile.txt\nfile3.dat\n", capture_output=True)
    assert p.stdout.decode('utf-8').strip() == "STATUS: ERROR", "verify_restore did not output 'STATUS: ERROR' for invalid input"

    # Test EMPTY case
    p = subprocess.run([prog_path], input=b"", capture_output=True)
    assert p.stdout.decode('utf-8').strip() == "STATUS: EMPTY", "verify_restore did not output 'STATUS: EMPTY' for empty input"


def test_cron_configuration():
    cron_path = "/home/user/backup_cron.txt"
    assert os.path.isfile(cron_path), f"Cron file not found at {cron_path}"
    with open(cron_path, 'r') as f:
        content = f.read().strip()

    # Check for valid cron schedule
    assert re.search(r'^\s*\*/5\s+\*\s+\*\s+\*\s+\*\s+/home/user/run_tests\.sh\s*$', content, re.MULTILINE), \
        f"Cron configuration in {cron_path} is incorrect. Expected '*/5 * * * * /home/user/run_tests.sh'"


def test_pipeline_execution():
    script_path = "/home/user/run_tests.sh"
    assert os.path.isfile(script_path), f"Processing script not found at {script_path}"
    assert os.access(script_path, os.X_OK), f"Processing script at {script_path} is not executable"

    # Create a temporary clone to push from
    with tempfile.TemporaryDirectory() as tmpdir:
        subprocess.run(["git", "clone", "/home/user/backup_repo.git", tmpdir], check=True, capture_output=True)

        # Create restore.log
        log_content = "INFO starting\nRESTORED data1.dat\nIGNORED config.cfg\nRESTORED data2.dat\n"
        with open(os.path.join(tmpdir, "restore.log"), "w") as f:
            f.write(log_content)

        subprocess.run(["git", "config", "user.name", "Test"], cwd=tmpdir, check=True)
        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=tmpdir, check=True)
        subprocess.run(["git", "add", "restore.log"], cwd=tmpdir, check=True)
        subprocess.run(["git", "commit", "-m", "Add restore.log"], cwd=tmpdir, check=True, capture_output=True)
        subprocess.run(["git", "push", "origin", "master"], cwd=tmpdir, check=True, capture_output=True)

        p_rev = subprocess.run(["git", "rev-parse", "HEAD"], cwd=tmpdir, check=True, capture_output=True)
        newrev = p_rev.stdout.decode('utf-8').strip()

    # The post-receive hook should have created a job file
    job_file = f"/home/user/spool/{newrev}.job"
    assert os.path.isfile(job_file), f"Job file {job_file} was not created by the post-receive hook"

    # Run the processing script
    subprocess.run([script_path], check=True, capture_output=True)

    # Check results
    out_file = f"/home/user/results/{newrev}.out"
    assert os.path.isfile(out_file), f"Result file {out_file} was not created by the processing script"

    with open(out_file, 'r') as f:
        result = f.read().strip()

    assert result == "STATUS: OK, COUNT: 2", f"Result file {out_file} contained '{result}', expected 'STATUS: OK, COUNT: 2'"
    assert not os.path.exists(job_file), f"Job file {job_file} was not deleted after processing"


def test_hook_parses_every_input_line_and_writes_hash():
    hook = "/home/user/backup_repo.git/hooks/post-receive"
    oldrev = "0" * 40
    revs = [secrets.token_hex(20), secrets.token_hex(20), secrets.token_hex(20)]
    refs = [f"refs/heads/a-{uuid.uuid4().hex}", f"refs/heads/b-{uuid.uuid4().hex}", f"refs/tags/c-{uuid.uuid4().hex}"]
    payload = "".join(f"{oldrev} {rev} {ref}\n" for rev, ref in zip(revs, refs))

    try:
        p = subprocess.run([hook], input=payload.encode(), capture_output=True, timeout=10)
        assert p.returncode == 0, f"post-receive hook failed: {p.stderr.decode(errors='replace')}"
        for rev in revs:
            job = f"/home/user/spool/{rev}.job"
            assert os.path.isfile(job), f"Hook did not create {job}"
            with open(job) as f:
                assert f.read().strip() == rev, f"{job} does not contain its new revision"
    finally:
        for rev in revs:
            try:
                os.remove(f"/home/user/spool/{rev}.job")
            except FileNotFoundError:
                pass


def test_verify_restore_is_compiled_cpp_and_handles_generated_inputs():
    source = "/home/user/verify_restore.cpp"
    program = "/home/user/verify_restore"
    assert os.path.isfile(source), f"C++ source not found at {source}"
    with open(program, "rb") as f:
        assert f.read(4) == b"\x7fELF", "verify_restore is not a compiled ELF executable"

    cases = [(b"", "STATUS: EMPTY")]
    for _ in range(10):
        count = 3 + secrets.randbelow(8)
        names = [f"{secrets.token_hex(7)}_{i}.dat" for i in range(count)]
        cases.append((("\n".join(names) + "\n").encode(), f"STATUS: OK, COUNT: {count}"))

        bad_index = secrets.randbelow(count)
        bad_names = list(names)
        bad_names[bad_index] = f"{secrets.token_hex(8)}.{secrets.choice(['txt', 'bin', 'data', 'DAT'])}"
        cases.append((("\n".join(bad_names) + "\n").encode(), "STATUS: ERROR"))

    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "verify_restore")
        subprocess.run(["g++", source, "-o", rebuilt], check=True, capture_output=True, timeout=30)
        for input_data, expected in cases:
            for executable in (program, rebuilt):
                p = subprocess.run([executable], input=input_data, capture_output=True, timeout=5)
                assert p.returncode == 0, f"{executable} exited with {p.returncode}"
                actual = p.stdout.decode("utf-8").strip()
                assert actual == expected, f"For generated input, {executable} produced {actual!r}, expected {expected!r}"


def test_randomized_multi_job_pipeline():
    script = "/home/user/run_tests.sh"
    assert os.path.isfile(script), f"Processing script not found at {script}"
    assert os.access(script, os.X_OK), f"Processing script at {script} is not executable"
    with open(script) as f:
        script_text = f.read()
    assert re.search(r"\bgrep\b", script_text), "run_tests.sh does not use grep"
    assert re.search(r"\bawk\b", script_text), "run_tests.sh does not use awk"

    valid_count = 4 + secrets.randbelow(6)
    valid_names = [f"good_{secrets.token_hex(6)}_{i}.dat" for i in range(valid_count)]
    invalid_names = [
        f"first_{secrets.token_hex(6)}.dat",
        f"bad_{secrets.token_hex(6)}.txt",
        f"last_{secrets.token_hex(6)}.dat",
    ]
    logs_and_expected = [
        (
            "INFO begin\n"
            + "\n".join(f"RESTORED {name} extra-field" for name in valid_names)
            + "\nIGNORED decoy.dat\n",
            f"STATUS: OK, COUNT: {valid_count}",
        ),
        (
            "NOTICE begin\n"
            + "\n".join(f"RESTORED {name} trailing data" for name in invalid_names)
            + "\nSKIPPED harmless.dat\n",
            "STATUS: ERROR",
        ),
        ("INFO no restored files here\nIGNORED unused.dat\n", "STATUS: EMPTY"),
    ]

    revisions = []
    branch_prefix = f"verify-{uuid.uuid4().hex}"
    with tempfile.TemporaryDirectory() as tmpdir:
        subprocess.run(["git", "init", tmpdir], check=True, capture_output=True)
        subprocess.run(["git", "config", "user.name", "Generated Test"], cwd=tmpdir, check=True)
        subprocess.run(["git", "config", "user.email", "generated@example.com"], cwd=tmpdir, check=True)
        subprocess.run(["git", "remote", "add", "origin", "/home/user/backup_repo.git"], cwd=tmpdir, check=True)

        for index, (log_content, _) in enumerate(logs_and_expected):
            with open(os.path.join(tmpdir, "restore.log"), "w") as f:
                f.write(log_content)
            subprocess.run(["git", "add", "restore.log"], cwd=tmpdir, check=True)
            subprocess.run(["git", "commit", "-m", f"generated case {index}"], cwd=tmpdir, check=True, capture_output=True)
            rev = subprocess.run(["git", "rev-parse", "HEAD"], cwd=tmpdir, check=True, capture_output=True, text=True).stdout.strip()
            revisions.append(rev)
            subprocess.run(
                ["git", "push", "origin", f"HEAD:refs/heads/{branch_prefix}-{index}"],
                cwd=tmpdir,
                check=True,
                capture_output=True,
            )

    for rev in revisions:
        job = f"/home/user/spool/{rev}.job"
        assert os.path.isfile(job), f"Hook did not queue generated revision {rev}"
        with open(job) as f:
            assert f.read().strip() == rev

    subprocess.run([script], check=True, capture_output=True, timeout=30)

    for rev, (_, expected) in zip(revisions, logs_and_expected):
        result_path = f"/home/user/results/{rev}.out"
        job_path = f"/home/user/spool/{rev}.job"
        assert os.path.isfile(result_path), f"Missing result for generated revision {rev}"
        with open(result_path) as f:
            actual = f.read().strip()
        assert actual == expected, f"Generated revision {rev} produced {actual!r}, expected {expected!r}"
        assert not os.path.exists(job_path), f"Job {job_path} was not deleted"


def test_cron_has_exactly_one_line():
    with open("/home/user/backup_cron.txt") as f:
        lines = f.read().splitlines()
    assert lines == ["*/5 * * * * /home/user/run_tests.sh"], "backup_cron.txt must contain exactly the required cron line"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
