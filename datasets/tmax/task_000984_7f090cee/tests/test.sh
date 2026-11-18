#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import subprocess
import tempfile

REPO = "/home/user/uptime-monitor"
CALC = os.path.join(REPO, "uptime_calc.sh")
FUZZ = os.path.join(REPO, "fuzz_test.sh")


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=5, **kwargs)


def historical_result(commit):
    shown = run(["git", "-C", REPO, "show", f"{commit}:uptime_calc.sh"])
    assert shown.returncode == 0, f"Cannot read uptime_calc.sh from commit {commit}."
    with tempfile.TemporaryDirectory() as td:
        path = os.path.join(td, "uptime_calc.sh")
        with open(path, "w") as f:
            f.write(shown.stdout)
        os.chmod(path, 0o700)
        result = run([path, "999", "1000"])
        return result.returncode, result.stdout.strip()


def test_on_main_branch():
    res = run(["git", "-C", REPO, "symbolic-ref", "--short", "HEAD"])
    assert res.returncode == 0 and res.stdout.strip() == "main", "Repository must be on the main branch."


def test_bad_commit_txt():
    path = "/home/user/bad_commit.txt"
    assert os.path.exists(path), f"File {path} does not exist."

    with open(path, "r") as f:
        commit_hash = f.read().strip()

    assert re.fullmatch(r"[0-9a-f]{40}", commit_hash), \
        "bad_commit.txt must contain one full 40-character lowercase SHA-1 hash."

    obj = run(["git", "-C", REPO, "cat-file", "-t", commit_hash])
    assert obj.returncode == 0 and obj.stdout.strip() == "commit", \
        f"'{commit_hash}' is not a valid commit."

    canonical = run(["git", "-C", REPO, "rev-parse", f"{commit_hash}^{{commit}}"])
    assert canonical.returncode == 0 and canonical.stdout.strip() == commit_hash

    commits_res = run(["git", "-C", REPO, "rev-list", "--first-parent", "--reverse", "main"])
    assert commits_res.returncode == 0, "Unable to inspect main history."
    commits = commits_res.stdout.splitlines()
    assert commit_hash in commits, "The reported commit is not in main's first-parent history."

    transitions = []
    previous_ok = None
    for commit in commits:
        rc, output = historical_result(commit)
        current_ok = rc == 0 and output == "99.90"
        if previous_ok is True and not current_ok:
            transitions.append(commit)
        previous_ok = current_ok

    assert len(transitions) == 1, \
        f"Expected exactly one good-to-bad regression in main history, found {len(transitions)}."
    assert commit_hash == transitions[0], \
        f"The reported hash is not the commit that first changed the calculation from good to bad."

    message = run(["git", "-C", REPO, "log", "--format=%B", "-n", "1", commit_hash])
    assert message.returncode == 0
    assert message.stdout.strip() == "Refactor calculation to avoid external dependencies", \
        f"The commit '{commit_hash}' does not have the expected regression commit message."

    parent = run(["git", "-C", REPO, "rev-parse", f"{commit_hash}^"])
    assert parent.returncode == 0, "The regression commit must have a parent."
    parent_rc, parent_output = historical_result(parent.stdout.strip())
    bad_rc, bad_output = historical_result(commit_hash)
    assert parent_rc == 0 and parent_output == "99.90", "The regression commit's parent was not working."
    assert bad_rc != 0 or bad_output != "99.90", "The reported commit does not introduce the precision bug."


def expected_percentage(successful, total):
    numerator = successful * 10000
    whole, remainder = divmod(numerator, total)
    assert remainder * 2 != total  # Avoid implementation-dependent exact half ties.
    if remainder * 2 > total:
        whole += 1
    return f"{whole // 100}.{whole % 100:02d}"


def test_uptime_calc_sh_fixed():
    assert os.path.isfile(CALC), f"Script {CALC} does not exist or is not a regular file."
    assert os.access(CALC, os.X_OK), f"Script {CALC} is not executable."

    cases = [(999, 1000), (5, 10)]
    rng = secrets.SystemRandom()
    while len(cases) < 42:
        total = rng.randint(2, 1_000_000)
        successful = rng.randint(1, total - 1)
        if (successful * 10000 % total) * 2 == total:
            continue
        pair = (successful, total)
        if pair not in cases:
            cases.append(pair)

    for successful, total in cases:
        res = run([CALC, str(successful), str(total)])
        assert res.returncode == 0, \
            f"uptime_calc.sh failed for {successful} {total}: {res.stderr!r}"
        output = res.stdout.strip()
        expected = expected_percentage(successful, total)
        assert re.fullmatch(r"[0-9]+\.[0-9]{2}", output), \
            f"Output for {successful} {total} is not formatted to exactly two decimal places: {output!r}"
        assert output == expected, \
            f"Expected {expected!r} for {successful} {total}, but got {output!r}."


def read_calls(log_path):
    calls = []
    if not os.path.exists(log_path):
        return calls
    with open(log_path) as f:
        for line in f:
            fields = line.strip().split()
            assert len(fields) == 2, f"Invalid calculator invocation recorded: {line!r}"
            assert all(re.fullmatch(r"[0-9]+", value) for value in fields), \
                f"fuzz_test.sh passed non-integer arguments: {fields!r}"
            successful, total = map(int, fields)
            assert 0 < successful < total, \
                f"fuzz_test.sh must generate 0 < successful_requests < total_requests, got {fields!r}"
            calls.append((successful, total))
    return calls


def write_probe(body):
    with open(CALC, "w") as f:
        f.write(body)
    os.chmod(CALC, 0o755)


def test_fuzz_test_sh():
    assert os.path.isfile(FUZZ), f"File {FUZZ} does not exist or is not a regular file."
    assert os.access(FUZZ, os.X_OK), f"File {FUZZ} is not executable."

    with tempfile.TemporaryDirectory() as td:
        backup = os.path.join(td, "uptime_calc.sh.backup")
        log_path = os.path.join(td, "calls.log")
        shutil.copy2(CALC, backup)
        env = os.environ.copy()
        env["PROBE_LOG"] = log_path

        try:
            for zero_output in ("0", "0.00"):
                open(log_path, "w").close()
                write_probe(
                    "#!/bin/bash\n"
                    "printf '%s %s\\n' \"$1\" \"$2\" >> \"$PROBE_LOG\"\n"
                    f"echo '{zero_output}'\n"
                )
                result = run([FUZZ], env=env)
                assert result.returncode == 1, \
                    f"fuzz_test.sh should exit 1 when uptime_calc.sh outputs exactly {zero_output!r}."
                assert read_calls(log_path), "fuzz_test.sh did not run uptime_calc.sh."

            open(log_path, "w").close()
            write_probe(
                "#!/bin/bash\n"
                "printf '%s %s\\n' \"$1\" \"$2\" >> \"$PROBE_LOG\"\n"
                "if (( $1 % 2 )); then echo '37.25'; else echo '82.75'; fi\n"
            )

            observed = []
            for _ in range(12):
                before = len(read_calls(log_path))
                result = run([FUZZ], env=env)
                assert result.returncode == 0, \
                    "fuzz_test.sh should exit 0 when the calculator returns a non-zero percentage."
                current = read_calls(log_path)
                assert len(current) > before, "Each fuzz_test.sh run must invoke uptime_calc.sh."
                observed.extend(current[before:])

            assert len(set(observed)) >= 2, \
                "Repeated fuzz_test.sh runs always used the same request counts; it must generate random values."
        finally:
            shutil.copy2(backup, CALC)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
