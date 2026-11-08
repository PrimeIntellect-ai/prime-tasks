#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import shutil
import stat
import string
import subprocess
import tempfile
import uuid

REPO = "/home/user/config-repo.git"
VALIDATOR = "/home/user/sec-validator"
SOURCE = "/home/user/sec-validator.c"
HOOK = "/home/user/config-repo.git/hooks/pre-receive"


def run(cmd, **kwargs):
    return subprocess.run(cmd, **kwargs)


def test_bare_repo_exists():
    assert os.path.isdir(REPO), f"Bare repository directory {REPO} does not exist."
    assert os.path.isdir(os.path.join(REPO, "objects")), f"{REPO} does not appear to be a bare Git repository."
    result = run(["git", "--git-dir", REPO, "rev-parse", "--is-bare-repository"], capture_output=True, text=True)
    assert result.returncode == 0 and result.stdout.strip() == "true", f"{REPO} is not a valid bare Git repository."


def test_validator_compiled_and_executable():
    assert os.path.isfile(SOURCE), f"Validator source {SOURCE} does not exist."
    assert os.path.isfile(VALIDATOR), f"Validator executable {VALIDATOR} does not exist."
    assert os.access(VALIDATOR, os.X_OK), f"Validator executable {VALIDATOR} is not executable."
    with open(VALIDATOR, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Validator is not a compiled native executable."


def test_pre_receive_hook_exists_and_executable():
    assert os.path.isfile(HOOK), f"Pre-receive hook {HOOK} does not exist."
    assert os.access(HOOK, os.X_OK), f"Pre-receive hook {HOOK} is not executable."
    with open(HOOK, "rb") as f:
        first_line = f.readline().decode("utf-8", "replace")
    assert first_line.startswith("#!") and "bash" in first_line, "Pre-receive hook is not an executable bash script."


def invoke_validator(path, contents, expected, tmpdir, index):
    conf = os.path.join(tmpdir, f"case-{index}-{uuid.uuid4().hex}.conf")
    with open(conf, "wb") as f:
        f.write(contents)
    result = run([path, conf], capture_output=True)
    assert result.returncode == expected, (
        f"Validator {path} returned {result.returncode}, expected {expected}, "
        f"for content {contents!r}."
    )


def test_validator_logic_and_submitted_c_source():
    with tempfile.TemporaryDirectory() as tmpdir:
        rebuilt = os.path.join(tmpdir, "rebuilt-validator")
        build = run(["gcc", SOURCE, "-o", rebuilt], capture_output=True, text=True)
        assert build.returncode == 0, f"Submitted C source does not compile with gcc: {build.stderr}"
        assert os.access(rebuilt, os.X_OK)

        # Preserve the original fixed semantic checks.
        fixed = [
            (b"NETWORK_MODE=isolated\nUSER_MODE=normal\n", 0),
            (b"USER_MODE=normal\n", 1),
            (b"NETWORK_MODE=isolated\nROOT_LOGIN=true\n", 1),
        ]

        rng = random.SystemRandom()
        generated = []
        near_matches = [
            "NETWORK_MODE=isolated ",
            " NETWORK_MODE=isolated",
            "NETWORK_MODE=isolated-extra",
            "network_mode=isolated",
            "ROOT_LOGIN=true ",
            " ROOT_LOGIN=true",
            "ROOT_LOGIN=True",
            "XROOT_LOGIN=true",
        ]
        for _ in range(40):
            has_required = bool(rng.getrandbits(1))
            has_forbidden = bool(rng.getrandbits(1))
            lines = []
            for _ in range(rng.randrange(0, 7)):
                token = "".join(rng.choice(string.ascii_letters + string.digits + "_-") for _ in range(rng.randrange(3, 18)))
                lines.append("KEY_" + token + "=" + uuid.uuid4().hex)
            lines.extend(rng.sample(near_matches, rng.randrange(0, len(near_matches) + 1)))
            if has_required:
                lines.insert(rng.randrange(len(lines) + 1), "NETWORK_MODE=isolated")
            if has_forbidden:
                lines.insert(rng.randrange(len(lines) + 1), "ROOT_LOGIN=true")
            rng.shuffle(lines)
            ending = "\n" if rng.getrandbits(1) else ""
            contents = ("\n".join(lines) + ending).encode()
            generated.append((contents, 0 if has_required and not has_forbidden else 1))

        for executable in (VALIDATOR, rebuilt):
            for i, (contents, expected) in enumerate(fixed + generated):
                invoke_validator(executable, contents, expected, tmpdir, i)
            assert run([executable], capture_output=True).returncode == 1, "Validator must return 1 when no argument is supplied."
            assert run([executable, "/definitely/missing/file", "extra"], capture_output=True).returncode == 1, "Validator must return 1 when more than one argument is supplied."
            assert run([executable, "/definitely/missing/file"], capture_output=True).returncode == 1, "Validator must return 1 when the file cannot be opened."


def test_git_hook_integration_generalized():
    token = uuid.uuid4().hex
    marker_dir = os.path.join(tempfile.gettempdir(), "validator-calls-" + token)
    os.mkdir(marker_dir)
    force_fail = os.path.join(marker_dir, "force-fail")
    backup = os.path.join(tempfile.gettempdir(), "sec-validator-real-" + token)
    original_mode = stat.S_IMODE(os.stat(VALIDATOR).st_mode)

    # Interpose on the required validator path so the test proves that the hook
    # invokes it with extracted incoming content and obeys its exit status.
    os.replace(VALIDATOR, backup)
    wrapper = f'''#!/bin/bash
set -u
src="$1"
out={marker_dir!r}/call.$BASHPID.$RANDOM.$RANDOM
cp -- "$src" "$out" 2>/dev/null || true
if [ -e {force_fail!r} ]; then
    exit 1
fi
exec {backup!r} "$@"
'''
    with open(VALIDATOR, "w") as f:
        f.write(wrapper)
    os.chmod(VALIDATOR, 0o755)

    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            work = os.path.join(tmpdir, "work")
            os.mkdir(work)
            run(["git", "init"], cwd=work, check=True, capture_output=True)
            run(["git", "config", "user.name", "Tester"], cwd=work, check=True)
            run(["git", "config", "user.email", "tester@example.com"], cwd=work, check=True)
            run(["git", "remote", "add", "origin", REPO], cwd=work, check=True)

            def write(relpath, data):
                path = os.path.join(work, relpath)
                os.makedirs(os.path.dirname(path), exist_ok=True) if os.path.dirname(path) != work else None
                with open(path, "w") as f:
                    f.write(data)

            def commit(message, paths=None):
                if paths is None:
                    run(["git", "add", "-A"], cwd=work, check=True)
                else:
                    run(["git", "add", "--"] + paths, cwd=work, check=True)
                run(["git", "commit", "-m", message], cwd=work, check=True, capture_output=True)
                return run(["git", "rev-parse", "HEAD"], cwd=work, check=True, capture_output=True, text=True).stdout.strip()

            def push(specs):
                return run(["git", "push", "origin"] + specs, cwd=work, capture_output=True, text=True)

            def assert_rejected(result, message):
                assert result.returncode != 0, message
                combined = result.stdout + result.stderr
                assert "Validation failed" in combined, "Rejected invalid push did not print 'Validation failed'."

            main_ref = "refs/heads/verify-main-" + token
            write("valid.conf", "NETWORK_MODE=isolated\nUSER_MODE=normal\n")
            base = commit("valid base")
            result = push(["HEAD:" + main_ref])
            assert result.returncode == 0, "Failed to push a valid configuration on initial ref creation."

            # An invalid update to an existing ref must be rejected.
            write("missing.conf", "USER_MODE=normal\n")
            commit("missing required mode")
            assert_rejected(push(["HEAD:" + main_ref]), "Hook accepted an update missing NETWORK_MODE=isolated.")
            run(["git", "reset", "--hard", base], cwd=work, check=True, capture_output=True)

            # An invalid newly-created ref must also be rejected; this closes the
            # accept-all-creations/reject-all-updates shortcut.
            write("root-login.conf", "NETWORK_MODE=isolated\nROOT_LOGIN=true\n")
            commit("forbidden root login")
            new_bad_ref = "refs/heads/verify-new-bad-" + token
            assert_rejected(push(["HEAD:" + new_bad_ref]), "Hook accepted an invalid configuration on new-ref creation.")
            run(["git", "reset", "--hard", base], cwd=work, check=True, capture_output=True)

            # An update touching no .conf files must be allowed.
            write("README.txt", "unrelated-" + uuid.uuid4().hex + "\n")
            nonconf = commit("non-conf update")
            result = push(["HEAD:" + main_ref])
            assert result.returncode == 0, "Hook rejected an update that modified no .conf files."

            # Exercise a randomly named .conf file containing misleading near matches.
            odd_name = "nested dir/device " + token[:8] + ".conf"
            valid_random = (
                "ROOT_LOGIN=true \n"
                "NETWORK_MODE=isolated-extra\n"
                "RANDOM_VALUE=" + uuid.uuid4().hex + "\n"
                "NETWORK_MODE=isolated\n"
            )
            write(odd_name, valid_random)
            valid_commit = commit("valid randomly named config")
            result = push(["HEAD:" + main_ref])
            assert result.returncode == 0, "Hook rejected a valid added .conf file."

            # Force an otherwise valid incoming file to fail solely through the
            # required validator, proving the hook invokes and honors it.
            forced_name = "forced-" + token + ".conf"
            forced_content = "TOKEN=" + uuid.uuid4().hex + "\nNETWORK_MODE=isolated\n"
            write(forced_name, forced_content)
            forced_commit = commit("validator invocation probe")
            open(force_fail, "w").close()
            assert_rejected(push(["HEAD:" + main_ref]), "Hook ignored a failure from /home/user/sec-validator.")
            os.unlink(force_fail)
            captured = []
            for name in os.listdir(marker_dir):
                if name.startswith("call."):
                    with open(os.path.join(marker_dir, name), "rb") as f:
                        captured.append(f.read())
            assert forced_content.encode() in captured, "Hook did not pass the incoming .conf content to /home/user/sec-validator."
            result = push(["HEAD:" + main_ref])
            assert result.returncode == 0, "Hook rejected the same valid content after validator success."

            # Modification of an existing .conf file must be validated.
            write(forced_name, "NETWORK_MODE=isolated\nROOT_LOGIN=true\nTOKEN=" + uuid.uuid4().hex + "\n")
            commit("invalidate existing config")
            assert_rejected(push(["HEAD:" + main_ref]), "Hook accepted an invalid modification of an existing .conf file.")
            run(["git", "reset", "--hard", forced_commit], cwd=work, check=True, capture_output=True)

            # A multi-ref receive containing one invalid ref must reject the whole push.
            write("batch-good.conf", "NETWORK_MODE=isolated\nVALUE=" + uuid.uuid4().hex + "\n")
            good_batch = commit("good batch ref")
            write("batch-bad.conf", "VALUE=" + uuid.uuid4().hex + "\n")
            bad_batch = commit("bad batch ref")
            good_ref = "refs/heads/verify-batch-good-" + token
            bad_ref = "refs/heads/verify-batch-bad-" + token
            result = push([good_batch + ":" + good_ref, bad_batch + ":" + bad_ref])
            assert_rejected(result, "Hook accepted a multi-ref push containing an invalid configuration.")
            for ref in (good_ref, bad_ref):
                shown = run(["git", "--git-dir", REPO, "show-ref", "--verify", ref], capture_output=True)
                assert shown.returncode != 0, "Pre-receive rejection did not reject the entire multi-ref push."
    finally:
        try:
            if os.path.exists(VALIDATOR):
                os.unlink(VALIDATOR)
            os.replace(backup, VALIDATOR)
            os.chmod(VALIDATOR, original_mode)
        finally:
            shutil.rmtree(marker_dir, ignore_errors=True)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
