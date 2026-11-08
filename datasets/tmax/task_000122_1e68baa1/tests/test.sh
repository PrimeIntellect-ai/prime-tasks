#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import subprocess
import tempfile
import uuid
import zipfile


def test_vm_user_sync_installed_and_lint_passes():
    venv_bin = "/home/user/venv/bin/vm-user-sync"
    assert os.path.isfile(venv_bin), f"Executable {venv_bin} is missing."
    assert os.access(venv_bin, os.X_OK), f"Executable {venv_bin} is not executable."

    result = subprocess.run([venv_bin, "--lint-templates"], capture_output=True, text=True)
    assert result.returncode == 0, f"vm-user-sync lint failed. Output: {result.stdout} {result.stderr}"

    venv_python = "/home/user/venv/bin/python"
    assert os.path.isfile(venv_python), "The requested virtual environment is missing its Python executable."
    probe = subprocess.run(
        [venv_python, "-c", """
import importlib.metadata
import json
import os
import vm_user_sync
p = os.path.join(os.path.dirname(vm_user_sync.__file__), 'templates', 'user-service.jinja')
print(json.dumps({'version': importlib.metadata.version('vm-user-sync'), 'template': open(p).read()}))
"""],
        capture_output=True,
        text=True,
    )
    assert probe.returncode == 0, f"vm-user-sync is not actually installed in the venv: {probe.stderr}"
    installed = json.loads(probe.stdout.strip())
    assert installed["version"] == "1.0.0"
    assert "After=network.target" in installed["template"]


def test_source_makefile_template_and_fresh_wheel_build():
    source = "/app/vm-user-sync-1.0.0"
    makefile = os.path.join(source, "Makefile")
    template = os.path.join(source, "vm_user_sync", "templates", "user-service.jinja")
    assert os.path.isfile(makefile), "Vendored Makefile is missing."
    assert os.path.isfile(template), "Vendored systemd template is missing."

    with open(makefile, "r") as f:
        make_text = f.read()
    assert re.search(r"(?m)^build\s*:\s*$", make_text), "Makefile has no build target."
    assert re.search(r"(?m)^\t+python3 setup\.py bdist_wheel\s*$", make_text), \
        "The bdist_wheel recipe must use a Make-compatible tab."

    with open(template, "r") as f:
        template_text = f.read()
    unit_match = re.search(r"(?ms)^\[Unit\]\s*$(.*?)(?=^\[|\Z)", template_text)
    assert unit_match, "Template has no [Unit] section."
    assert re.search(r"(?m)^After=network\.target\s*$", unit_match.group(1)), \
        "After=network.target is missing from the [Unit] section."

    with tempfile.TemporaryDirectory(prefix="wheel-build-") as td:
        copied = os.path.join(td, "src")
        shutil.copytree(source, copied, symlinks=True)
        for name in ("build", "dist", "vm_user_sync.egg-info"):
            path = os.path.join(copied, name)
            if os.path.isdir(path):
                shutil.rmtree(path)
            elif os.path.exists(path):
                os.unlink(path)
        built = subprocess.run(["make", "build"], cwd=copied, capture_output=True, text=True)
        assert built.returncode == 0, f"A fresh make build failed:\n{built.stdout}\n{built.stderr}"
        wheels = [os.path.join(copied, "dist", n) for n in os.listdir(os.path.join(copied, "dist")) if n.endswith(".whl")]
        assert wheels, "make build did not produce a wheel."
        with zipfile.ZipFile(wheels[0]) as wheel:
            members = [n for n in wheel.namelist() if n.endswith("vm_user_sync/templates/user-service.jinja")]
            assert members, "Built wheel does not contain the systemd template."
            wheel_template = wheel.read(members[0]).decode("utf-8")
            assert "After=network.target" in wheel_template, "Built wheel contains an unfixed template."


def test_git_repo_and_hook():
    repo_path = "/home/user/provisioning.git"
    assert os.path.isdir(repo_path), f"Git repo {repo_path} is missing."

    result = subprocess.run(["git", "-C", repo_path, "rev-parse", "--is-bare-repository"], capture_output=True, text=True)
    assert result.returncode == 0 and result.stdout.strip() == "true", f"Repository at {repo_path} is not a bare Git repository."

    hook_path = os.path.join(repo_path, "hooks", "pre-receive")
    assert os.path.isfile(hook_path), f"Hook {hook_path} is missing."
    assert os.access(hook_path, os.X_OK), f"Hook {hook_path} is not executable."

    with open(hook_path, "r") as f:
        content = f.read()
    assert "# VALIDATOR_INTEGRATION_READY" in content, f"Hook {hook_path} is missing the placeholder comment."


def run_validator(path):
    return subprocess.run(["python3", "/home/user/validator.py", path], capture_output=True, text=True).returncode


def test_validator_against_corpus():
    validator_script = "/home/user/validator.py"
    assert os.path.isfile(validator_script), f"Validator script {validator_script} is missing."

    clean_base = "/app/corpus/clean"
    evil_base = "/app/corpus/evil"

    clean_dirs = [os.path.join(clean_base, d) for d in os.listdir(clean_base) if os.path.isdir(os.path.join(clean_base, d))]
    evil_dirs = [os.path.join(evil_base, d) for d in os.listdir(evil_base) if os.path.isdir(os.path.join(evil_base, d))]

    clean_failed = []
    for d in clean_dirs:
        res = subprocess.run(["python3", validator_script, d], capture_output=True)
        if res.returncode != 0:
            clean_failed.append(os.path.basename(d))

    evil_failed = []
    for d in evil_dirs:
        res = subprocess.run(["python3", validator_script, d], capture_output=True)
        if res.returncode != 1:
            evil_failed.append(os.path.basename(d))

    errors = []
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_dirs)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_dirs)} clean modified/rejected: {', '.join(clean_failed)}")

    assert not errors, "Validator corpus test failed: " + "; ".join(errors)


def test_validator_on_generated_unpredictable_inputs():
    validator = "/home/user/validator.py"
    assert os.path.isfile(validator), f"Validator script {validator} is missing."

    with tempfile.TemporaryDirectory(prefix="validator-cases-") as td:
        clean = os.path.join(td, "clean-" + uuid.uuid4().hex)
        nested = os.path.join(clean, "nested-" + uuid.uuid4().hex)
        os.makedirs(nested)
        with open(os.path.join(clean, "identity.ssh_key"), "w") as f:
            f.write("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA clean@example\n")
        with open(os.path.join(nested, "schedule.cron"), "w") as f:
            f.write("15 3 * * * /usr/bin/python3 /srv/task.py\n")
        with open(os.path.join(nested, "ordinary.txt"), "w") as f:
            f.write("ordinary configuration\n")
        os.symlink(os.path.join("nested-" + os.path.basename(nested).split("nested-", 1)[1], "schedule.cron"), os.path.join(clean, "internal-link"))
        assert run_validator(clean) == 0, "Generated clean directory was rejected."

        for suffix, body in [
            (".ssh_key", 'command="/usr/bin/id" ssh-ed25519 AAAA\n'),
            (".cron", "* * * * * curl https://example.invalid/x\n"),
            (".cron", "* * * * * wget https://example.invalid/x\n"),
            (".cron", "* * * * * nc 127.0.0.1 9999\n"),
            (".cron", "* * * * * bash /tmp/job.sh\n"),
        ]:
            case = os.path.join(td, "evil-" + uuid.uuid4().hex)
            deep = os.path.join(case, "a-" + uuid.uuid4().hex, "b-" + uuid.uuid4().hex)
            os.makedirs(deep)
            with open(os.path.join(deep, uuid.uuid4().hex + suffix), "w") as f:
                f.write(body)
            assert run_validator(case) == 1, f"Generated malicious {suffix} content was accepted: {body!r}"

        outside = os.path.join(td, "outside-" + uuid.uuid4().hex)
        with open(outside, "w") as f:
            f.write("outside\n")
        escape_case = os.path.join(td, "escape-" + uuid.uuid4().hex)
        os.makedirs(os.path.join(escape_case, "nested"))
        link_path = os.path.join(escape_case, "nested", "escape-" + uuid.uuid4().hex)
        os.symlink(os.path.relpath(outside, os.path.dirname(link_path)), link_path)
        assert run_validator(escape_case) == 1, "A generated relative symlink escape was accepted."

        missing = os.path.join(td, "missing-" + uuid.uuid4().hex)
        assert run_validator(missing) == 1, "A nonexistent configuration path was not treated as invalid."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
