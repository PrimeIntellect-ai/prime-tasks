#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import secrets
import shutil
import subprocess
import sys
import tarfile
import tempfile

TARBALL_PATH = '/home/user/curated_configs.tar.gz'
EXTRACTED_DIR = '/home/user/extracted'
RULES_PATH = '/home/user/curation_rules.ini'
START = b'--CONFIG_START--'
END = b'--CONFIG_END--'


def test_tarball_exists():
    assert os.path.isfile(TARBALL_PATH), f"The tarball {TARBALL_PATH} does not exist."


def test_tarball_contents():
    assert tarfile.is_tarfile(TARBALL_PATH), f"{TARBALL_PATH} is not a valid tar archive."

    with tempfile.TemporaryDirectory() as tmpdir:
        with tarfile.open(TARBALL_PATH, 'r:gz') as tar:
            tar.extractall(path=tmpdir)

            extracted_base = os.path.join(tmpdir, 'extracted')
            assert os.path.isdir(extracted_base), "The tarball must contain an 'extracted/' directory at its root."

            serviceA_path = os.path.join(extracted_base, 'serviceA.conf')
            assert os.path.isfile(serviceA_path), "extracted/serviceA.conf is missing from the tarball."
            with open(serviceA_path, 'r', encoding='utf-8') as f:
                contentA = f.read()
            assert contentA == "loglevel=DEBUG\nenv=PROD", "Incorrect content in extracted/serviceA.conf"

            serviceB_path = os.path.join(extracted_base, 'serviceB.conf')
            assert os.path.isfile(serviceB_path), "extracted/serviceB.conf is missing from the tarball."
            with open(serviceB_path, 'r', encoding='utf-8') as f:
                contentB = f.read()
            assert contentB == "loglevel=INFO\nenv=STAGING", "Incorrect content in extracted/serviceB.conf"

            serviceC_path = os.path.join(extracted_base, 'serviceC.conf')
            assert not os.path.exists(serviceC_path), "extracted/serviceC.conf should not exist (size < 1000)."

            serviceD_path = os.path.join(extracted_base, 'serviceD.conf')
            assert not os.path.exists(serviceD_path), "extracted/serviceD.conf should not exist (wrong extension)."


def test_extracted_directory_contents():
    assert os.path.isdir(EXTRACTED_DIR), f"The directory {EXTRACTED_DIR} does not exist."

    serviceA_path = os.path.join(EXTRACTED_DIR, 'serviceA.conf')
    assert os.path.isfile(serviceA_path), f"{serviceA_path} is missing."
    with open(serviceA_path, 'r', encoding='utf-8') as f:
        contentA = f.read()
    assert contentA == "loglevel=DEBUG\nenv=PROD", f"Incorrect content in {serviceA_path}"

    serviceB_path = os.path.join(EXTRACTED_DIR, 'serviceB.conf')
    assert os.path.isfile(serviceB_path), f"{serviceB_path} is missing."
    with open(serviceB_path, 'r', encoding='utf-8') as f:
        contentB = f.read()
    assert contentB == "loglevel=INFO\nenv=STAGING", f"Incorrect content in {serviceB_path}"

    serviceC_path = os.path.join(EXTRACTED_DIR, 'serviceC.conf')
    assert not os.path.exists(serviceC_path), f"{serviceC_path} should not exist."

    serviceD_path = os.path.join(EXTRACTED_DIR, 'serviceD.conf')
    assert not os.path.exists(serviceD_path), f"{serviceD_path} should not exist."


def find_python_scripts():
    candidates = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d not in {'artifacts', 'extracted', '__pycache__'} and not d.startswith('.')]
        for name in files:
            path = os.path.join(root, name)
            if path in {TARBALL_PATH, RULES_PATH} or os.path.islink(path):
                continue
            try:
                if os.path.getsize(path) > 2_000_000:
                    continue
                with open(path, 'rb') as f:
                    prefix = f.read(128)
            except OSError:
                continue
            if name.endswith('.py') or (prefix.startswith(b'#!') and b'python' in prefix.lower()):
                candidates.append(path)
    return sorted(candidates)


def uses_mmap(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            tree = ast.parse(f.read(), filename=path)
    except (OSError, UnicodeError, SyntaxError):
        return False

    module_aliases = set()
    function_aliases = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'mmap':
                    module_aliases.add(alias.asname or 'mmap')
        elif isinstance(node, ast.ImportFrom) and node.module == 'mmap':
            for alias in node.names:
                if alias.name == 'mmap':
                    function_aliases.add(alias.asname or 'mmap')

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name) and node.func.id in function_aliases:
            return True
        if (isinstance(node.func, ast.Attribute) and node.func.attr == 'mmap'
                and isinstance(node.func.value, ast.Name)
                and node.func.value.id in module_aliases):
            return True
    return False


def write_blob(path, total_size, text, prefix_size):
    payload = text.encode('utf-16le')
    suffix_size = total_size - prefix_size - len(START) - len(payload) - len(END)
    assert suffix_size >= 0
    with open(path, 'wb') as f:
        f.write(b'P' * prefix_size)
        f.write(START)
        f.write(payload)
        f.write(END)
        f.write(b'S' * suffix_size)
    assert os.path.getsize(path) == total_size


def prepare_dynamic_fixture(base, extension, minimum, valid_data, below_name, wrong_name):
    shutil.rmtree(base, ignore_errors=True)
    os.makedirs(base)
    shutil.rmtree(EXTRACTED_DIR, ignore_errors=True)
    os.makedirs(EXTRACTED_DIR)
    if os.path.lexists(TARBALL_PATH):
        os.remove(TARBALL_PATH)

    with open(RULES_PATH, 'w', encoding='utf-8') as f:
        f.write('[Target]\n')
        f.write(f'directory = {base}\n')
        f.write(f'extension = {extension}\n')
        f.write(f'min_size_bytes = {minimum}\n')

    sizes = [minimum, minimum + 317]
    prefixes = [173, 286]
    for (stem, text), size, prefix in zip(valid_data.items(), sizes, prefixes):
        write_blob(os.path.join(base, stem + extension), size, text, prefix)
    write_blob(os.path.join(base, below_name + extension), minimum - 1, 'below=' + secrets.token_hex(8), 91)
    write_blob(os.path.join(base, wrong_name + '.wrong'), minimum + 200, 'wrong=' + secrets.token_hex(8), 117)


def dynamic_result_is_correct(valid_data, below_name, wrong_name):
    expected_names = {stem + '.conf' for stem in valid_data}
    if not os.path.isdir(EXTRACTED_DIR) or not tarfile.is_tarfile(TARBALL_PATH):
        return False

    actual_names = {
        name for name in os.listdir(EXTRACTED_DIR)
        if os.path.isfile(os.path.join(EXTRACTED_DIR, name))
    }
    if actual_names != expected_names:
        return False
    if os.path.exists(os.path.join(EXTRACTED_DIR, below_name + '.conf')):
        return False
    if os.path.exists(os.path.join(EXTRACTED_DIR, wrong_name + '.conf')):
        return False

    for stem, expected in valid_data.items():
        try:
            with open(os.path.join(EXTRACTED_DIR, stem + '.conf'), 'r', encoding='utf-8') as f:
                if f.read() != expected:
                    return False
        except (OSError, UnicodeError):
            return False

    with tempfile.TemporaryDirectory() as tmpdir:
        try:
            with tarfile.open(TARBALL_PATH, 'r:gz') as tar:
                tar.extractall(tmpdir)
        except (OSError, tarfile.TarError):
            return False
        archived = os.path.join(tmpdir, 'extracted')
        if not os.path.isdir(archived):
            return False
        archived_names = {
            name for name in os.listdir(archived)
            if os.path.isfile(os.path.join(archived, name))
        }
        if archived_names != expected_names:
            return False
        for stem, expected in valid_data.items():
            try:
                with open(os.path.join(archived, stem + '.conf'), 'r', encoding='utf-8') as f:
                    if f.read() != expected:
                        return False
            except (OSError, UnicodeError):
                return False
    return True


def test_script_on_randomized_inputs():
    token = secrets.token_hex(8)
    base = '/home/user/verification_artifacts_' + token
    extension = '.fixture_' + token
    minimum = 1400
    valid_data = {
        'alpha_' + token: 'token=' + secrets.token_hex(24) + '\nmode=Δelta',
        'beta_' + token: 'owner=' + secrets.token_hex(20) + '\nmessage=配置-' + token,
    }
    below_name = 'below_' + token
    wrong_name = 'wrong_' + token

    candidates = [path for path in find_python_scripts() if uses_mmap(path)]
    assert candidates, 'No Python extraction script using mmap was found under /home/user.'

    errors = []
    for candidate in candidates:
        prepare_dynamic_fixture(base, extension, minimum, valid_data, below_name, wrong_name)
        try:
            result = subprocess.run(
                [sys.executable, candidate],
                cwd=os.path.dirname(candidate) or '/home/user',
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=20,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            errors.append(f'{candidate}: {exc}')
            continue
        if result.returncode == 0 and dynamic_result_is_correct(valid_data, below_name, wrong_name):
            return
        errors.append(f'{candidate}: exit={result.returncode}, stderr={result.stderr[-300:]}')

    raise AssertionError('No mmap-using Python script correctly processed randomized rules and artifacts. ' + '; '.join(errors))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
