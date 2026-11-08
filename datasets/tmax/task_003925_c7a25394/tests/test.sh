#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import re
import secrets
import subprocess
import pytest
from datetime import datetime, timezone, timedelta

SCRIPT_PATH = '/home/user/init_microservice.py'
CONFIG_DIR = '/home/user/config'
CONFIG_FILE = '/home/user/config/app.env'


def read_config():
    with open(CONFIG_FILE, 'rb') as f:
        raw = f.read()
    try:
        text = raw.decode('utf-8')
    except UnicodeDecodeError as exc:
        pytest.fail(f'Config is not valid UTF-8: {exc}')

    assert '\r' not in text, 'Config must use exact LF-separated lines.'
    body = text[:-1] if text.endswith('\n') else text
    assert not body.endswith('\n'), 'Config contains extra blank lines.'
    lines = body.split('\n')
    assert len(lines) == 3, f'Config must contain exactly three lines, got {len(lines)}.'
    return text, lines


def parse_and_check_config(expected_tz, expected_locale, earliest=None, latest=None):
    _, lines = read_config()
    assert lines[0] == f'APP_TZ={expected_tz}', 'APP_TZ line is not exact.'
    assert lines[1] == f'APP_LOCALE={expected_locale}', 'APP_LOCALE line is not exact.'
    assert re.fullmatch(r'DEPLOY_TIME=.+', lines[2]), 'DEPLOY_TIME line is missing or malformed.'

    value = lines[2].split('=', 1)[1]
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        pytest.fail(f"DEPLOY_TIME '{value}' is not a valid ISO 8601 string.")

    if parsed.tzinfo is None:
        parsed_utc = parsed.replace(tzinfo=timezone.utc)
    else:
        assert parsed.utcoffset() == timedelta(0), 'DEPLOY_TIME must be expressed in UTC.'
        parsed_utc = parsed.astimezone(timezone.utc)

    if earliest is not None and latest is not None:
        assert earliest - timedelta(seconds=3) <= parsed_utc <= latest + timedelta(seconds=3), \
            f'DEPLOY_TIME {value} was not generated from the current UTC time.'
    return parsed_utc


def test_config_dir_exists():
    assert os.path.isdir(CONFIG_DIR), f'The directory {CONFIG_DIR} does not exist.'


def test_script_executable():
    assert os.path.isfile(SCRIPT_PATH), f'The script {SCRIPT_PATH} does not exist.'
    assert os.access(SCRIPT_PATH, os.X_OK), f'The script {SCRIPT_PATH} is not executable.'


def test_uses_argparse_with_required_options():
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f'Script is not valid Python: {exc}')

    argparse_aliases = set()
    constructor_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'argparse':
                    argparse_aliases.add(alias.asname or 'argparse')
        elif isinstance(node, ast.ImportFrom) and node.module == 'argparse':
            for alias in node.names:
                if alias.name == 'ArgumentParser':
                    constructor_names.add(alias.asname or alias.name)

    has_parser = False
    added_options = set()
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Attribute) and func.attr == 'ArgumentParser' \
                and isinstance(func.value, ast.Name) and func.value.id in argparse_aliases:
            has_parser = True
        elif isinstance(func, ast.Name) and func.id in constructor_names:
            has_parser = True
        if isinstance(func, ast.Attribute) and func.attr == 'add_argument':
            for arg in node.args:
                if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
                    added_options.add(arg.value)

    assert has_parser, 'Script must construct an argparse.ArgumentParser.'
    assert '--tz' in added_options, 'Script must define the --tz argparse option.'
    assert '--locale' in added_options, 'Script must define the --locale argparse option.'


def test_app_env_content_initial():
    assert os.path.isfile(CONFIG_FILE), f'The config file {CONFIG_FILE} does not exist.'

    with open(CONFIG_FILE, 'r') as f:
        content = f.read()

    assert 'APP_TZ=Asia/Tokyo' in content, 'APP_TZ is not set to Asia/Tokyo in the config file.'
    assert 'APP_LOCALE=ja_JP.UTF-8' in content, 'APP_LOCALE is not set to ja_JP.UTF-8 in the config file.'

    match = re.search(r'DEPLOY_TIME=(.*)', content)
    assert match is not None, 'DEPLOY_TIME is missing from the config file.'
    deploy_time_str = match.group(1).strip()
    try:
        datetime.fromisoformat(deploy_time_str)
    except ValueError:
        pytest.fail(f"DEPLOY_TIME '{deploy_time_str}' is not a valid ISO 8601 string.")

    mtime = datetime.fromtimestamp(os.path.getmtime(CONFIG_FILE), timezone.utc)
    parsed = parse_and_check_config('Asia/Tokyo', 'ja_JP.UTF-8')
    assert abs((parsed - mtime).total_seconds()) <= 10, \
        'Initial DEPLOY_TIME does not correspond to when the config was generated.'


def test_script_interactive_mode():
    start = datetime.now(timezone.utc)
    process = subprocess.Popen(
        [SCRIPT_PATH], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True
    )
    stdout, stderr = process.communicate(input='Europe/Paris\nfr_FR.UTF-8\n')
    end = datetime.now(timezone.utc)

    assert process.returncode == 0, f'Script failed in interactive mode: {stderr}'
    assert 'Enter timezone: ' in stdout, 'Script did not prompt for timezone correctly.'
    assert 'Enter locale: ' in stdout, 'Script did not prompt for locale correctly.'
    assert stdout == 'Enter timezone: Enter locale: ', 'Interactive prompts must use exactly the required strings.'

    with open(CONFIG_FILE, 'r') as f:
        content = f.read()
    assert 'APP_TZ=Europe/Paris' in content, 'Interactive mode did not set APP_TZ correctly.'
    assert 'APP_LOCALE=fr_FR.UTF-8' in content, 'Interactive mode did not set APP_LOCALE correctly.'
    assert 'DEPLOY_TIME=' in content, 'DEPLOY_TIME is missing after interactive mode.'
    parse_and_check_config('Europe/Paris', 'fr_FR.UTF-8', start, end)


def test_script_cli_args():
    start = datetime.now(timezone.utc)
    process = subprocess.run(
        [SCRIPT_PATH, '--tz', 'America/New_York', '--locale', 'en_US.UTF-8'],
        capture_output=True, text=True
    )
    end = datetime.now(timezone.utc)
    assert process.returncode == 0, 'Script failed when provided with CLI arguments.'

    with open(CONFIG_FILE, 'r') as f:
        content = f.read()
    assert 'APP_TZ=America/New_York' in content, 'CLI arguments did not set APP_TZ correctly.'
    assert 'APP_LOCALE=en_US.UTF-8' in content, 'CLI arguments did not set APP_LOCALE correctly.'
    assert 'DEPLOY_TIME=' in content, 'DEPLOY_TIME is missing after running with CLI arguments.'
    parse_and_check_config('America/New_York', 'en_US.UTF-8', start, end)


def test_randomized_cli_values_and_fresh_timestamp():
    token = secrets.token_hex(12)
    tz = f'Zone/{token}'
    locale = f'loc_{token}.UTF-8'
    start = datetime.now(timezone.utc)
    process = subprocess.run(
        [SCRIPT_PATH, '--locale', locale, '--tz', tz],
        capture_output=True, text=True, timeout=10
    )
    end = datetime.now(timezone.utc)
    assert process.returncode == 0, f'Randomized CLI invocation failed: {process.stderr}'
    parse_and_check_config(tz, locale, start, end)


def test_randomized_interactive_values_and_fresh_timestamp():
    token = secrets.token_hex(12)
    tz = f'Interactive/{token}'
    locale = f'int_{token}.UTF-8'
    start = datetime.now(timezone.utc)
    process = subprocess.run(
        [SCRIPT_PATH], input=f'{tz}\n{locale}\n', capture_output=True,
        text=True, timeout=10
    )
    end = datetime.now(timezone.utc)
    assert process.returncode == 0, f'Randomized interactive invocation failed: {process.stderr}'
    assert process.stdout == 'Enter timezone: Enter locale: ', \
        'Interactive prompts must use exactly the required strings.'
    parse_and_check_config(tz, locale, start, end)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
