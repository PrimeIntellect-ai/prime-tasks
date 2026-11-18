#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shlex
import stat
import subprocess
import uuid
from pathlib import Path

import pytest

PROJECT_DIR = Path('/home/user/project')
MAKEFILE_PATH = PROJECT_DIR / 'Makefile'
CI_YML_PATH = PROJECT_DIR / '.github' / 'workflows' / 'ci.yml'
CONFIG_PATH = PROJECT_DIR / 'build_config.json'


def load_config():
    with CONFIG_PATH.open() as f:
        return json.load(f)


def parse_makefile(path):
    raw_lines = path.read_text().splitlines()
    logical = []
    i = 0
    while i < len(raw_lines):
        line = raw_lines[i]
        if line.startswith('\t'):
            logical.append((line, True))
            i += 1
            continue
        while line.rstrip().endswith('\\') and i + 1 < len(raw_lines):
            line = line.rstrip()[:-1] + ' ' + raw_lines[i + 1].lstrip()
            i += 1
        logical.append((line, False))
        i += 1

    rules = {}
    first_normal_target = None
    current_targets = []
    for line, is_recipe in logical:
        if is_recipe:
            command = line[1:].strip()
            if command:
                for target in current_targets:
                    rules[target]['recipes'].append(command)
            continue

        current_targets = []
        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            continue
        body = line.split('#', 1)[0].strip()
        if not body or ':' not in body:
            continue
        left, right = body.split(':', 1)
        # Do not mistake variable assignments such as X := value for rules.
        if '=' in left or (right.startswith('=') and len(left.split()) == 1):
            continue
        targets = left.split()
        if not targets:
            continue
        prereq_text = right.split(';', 1)[0]
        prereqs = [p for p in prereq_text.replace('|', ' ').split() if p]
        current_targets = targets
        for target in targets:
            entry = rules.setdefault(target, {'prereqs': [], 'recipes': []})
            entry['prereqs'].extend(prereqs)
        if first_normal_target is None:
            normal = [t for t in targets if not t.startswith('.') and '%' not in t]
            if normal:
                first_normal_target = normal[0]
    return rules, first_normal_target


def normalized_command(command):
    command = command.lstrip('@-+').strip()
    try:
        return shlex.split(command)
    except ValueError:
        return []


def validate_makefile(config):
    assert MAKEFILE_PATH.is_file(), f'Makefile is missing at {MAKEFILE_PATH}'
    content = MAKEFILE_PATH.read_text()
    targets = config.get('targets', {})

    # Preserve the original content assertions.
    assert 'all:' in content, "Makefile must contain an 'all' target."
    for target_name, info in targets.items():
        assert f'{target_name}:' in content, f'Makefile missing rule for target: {target_name}'
        assert info['src'] in content, f'Makefile rule for {target_name} must depend on {info["src"]}'
        for dep in info['deps']:
            assert dep in content, f'Makefile rule for {target_name} must depend on {dep}'
        if info['lang'] == 'c':
            assert f'gcc {info["src"]} -o {target_name}' in content
        else:
            assert f'cp {info["src"]} {target_name}' in content
            assert f'chmod +x {target_name}' in content

    rules, first_target = parse_makefile(MAKEFILE_PATH)
    assert first_target == 'all', "The default first target must be 'all'."
    assert 'all' in rules, "Makefile must define an all rule."
    assert set(targets).issubset(set(rules['all']['prereqs'])), \
        "The all rule must explicitly depend on every configured target."

    for target_name, info in targets.items():
        assert target_name in rules, f'Missing actual rule for {target_name}'
        rule = rules[target_name]
        required = {info['src'], *info.get('deps', [])}
        assert required.issubset(set(rule['prereqs'])), \
            f'Rule {target_name} does not explicitly list its source and dependencies.'
        commands = [normalized_command(c) for c in rule['recipes']]
        if info['lang'] == 'c':
            assert ['gcc', info['src'], '-o', target_name] in commands, \
                f'Rule {target_name} lacks the required gcc recipe.'
        else:
            cp_cmd = ['cp', info['src'], target_name]
            chmod_cmd = ['chmod', '+x', target_name]
            assert cp_cmd in commands, f'Rule {target_name} lacks the required cp recipe.'
            assert chmod_cmd in commands, f'Rule {target_name} lacks the required chmod recipe.'
            assert commands.index(cp_cmd) < commands.index(chmod_cmd), \
                f'Rule {target_name} must copy before applying chmod.'


def load_yaml(path):
    ruby = r'''require "yaml"; require "json"; obj = YAML.safe_load(File.read(ARGV[0]), aliases: true); puts JSON.generate(obj)'''
    result = subprocess.run(
        ['ruby', '-e', ruby, str(path)], text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0, f'ci.yml is not valid YAML: {result.stderr}'
    return json.loads(result.stdout)


def validate_ci():
    assert CI_YML_PATH.is_file(), f'GitHub Actions workflow missing at {CI_YML_PATH}'
    content = CI_YML_PATH.read_text()

    # Preserve the original content assertions.
    assert 'push' in content and 'main' in content
    assert 'ubuntu-latest' in content
    assert 'actions/checkout@v3' in content
    assert 'make all' in content

    workflow = load_yaml(CI_YML_PATH)
    assert isinstance(workflow, dict), 'Workflow root must be a YAML mapping.'
    trigger = workflow.get('on', workflow.get('true'))
    assert isinstance(trigger, dict) and 'push' in trigger, 'Workflow must trigger on push.'
    push = trigger['push']
    assert isinstance(push, dict), 'Push trigger must configure the main branch.'
    branches = push.get('branches')
    if isinstance(branches, str):
        branches = [branches]
    assert isinstance(branches, list) and 'main' in branches, 'Push trigger must include main.'

    jobs = workflow.get('jobs')
    assert isinstance(jobs, dict) and list(jobs.keys()) == ['build'], \
        "Workflow must contain a single job named 'build'."
    build = jobs['build']
    assert isinstance(build, dict) and build.get('runs-on') == 'ubuntu-latest'
    steps = build.get('steps')
    assert isinstance(steps, list) and len(steps) == 2, 'Build job must have exactly two steps.'
    assert steps[0].get('name') == 'Checkout code'
    assert steps[0].get('uses') == 'actions/checkout@v3'
    assert steps[1].get('name') == 'Build all targets'
    assert steps[1].get('run') == 'make all'


def run_make_and_validate(config, goal='all'):
    for target in config['targets']:
        target_path = PROJECT_DIR / target
        if target_path.exists() and target_path.is_file():
            target_path.unlink()
    result = subprocess.run(
        ['make', '-B', goal], cwd=PROJECT_DIR, text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, \
        f"'make {goal}' failed.\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}"
    for target_name, info in config['targets'].items():
        target_path = PROJECT_DIR / target_name
        assert target_path.is_file(), f'Executable {target_name} was not created by make.'
        assert os.access(target_path, os.X_OK), f'File {target_name} is not executable.'
        if info['lang'] in ('python', 'ruby', 'bash'):
            assert target_path.read_bytes() == (PROJECT_DIR / info['src']).read_bytes(), \
                f'{target_name} was not copied from its configured source.'


def candidate_scripts(config):
    excluded = {
        CONFIG_PATH.resolve(), MAKEFILE_PATH.resolve(), CI_YML_PATH.resolve(),
        *(PROJECT_DIR / x for x in ['fetch.sh', 'clean.py', 'engine.c', 'report.rb']),
        *(PROJECT_DIR / name for name in config['targets']),
    }
    excluded = {Path(x).resolve() for x in excluded}
    candidates = []
    for path in PROJECT_DIR.rglob('*'):
        if not path.is_file() or path.resolve() in excluded or '.git' in path.parts:
            continue
        try:
            data = path.read_bytes()
        except OSError:
            continue
        if len(data) > 1024 * 1024 or b'\0' in data:
            continue
        suffix = path.suffix.lower()
        first = data.splitlines()[0] if data.splitlines() else b''
        if suffix in ('.py', '.rb', '.sh', '.bash', '.pl') or first.startswith(b'#!') or os.access(path, os.X_OK):
            candidates.append(path)
    return candidates


def commands_for(path):
    suffix = path.suffix.lower()
    if suffix == '.py':
        return [['python3', str(path)]]
    if suffix == '.rb':
        return [['ruby', str(path)]]
    if suffix in ('.sh', '.bash'):
        return [['bash', str(path)]]
    if suffix == '.pl':
        return [['perl', str(path)]]
    commands = []
    if os.access(path, os.X_OK):
        commands.append([str(path)])
    try:
        first = path.read_text(errors='ignore').splitlines()[0]
    except (OSError, IndexError):
        first = ''
    if 'python' in first:
        commands.append(['python3', str(path)])
    elif 'ruby' in first:
        commands.append(['ruby', str(path)])
    elif 'bash' in first or first.startswith('#!/bin/sh'):
        commands.append(['bash', str(path)])
    return commands


def test_artifacts_and_build():
    config = load_config()
    validate_makefile(config)
    validate_ci()
    run_make_and_validate(config)


def test_generator_parses_json_and_regenerates_artifacts():
    original_config_bytes = CONFIG_PATH.read_bytes()
    original_makefile = MAKEFILE_PATH.read_bytes()
    original_ci = CI_YML_PATH.read_bytes()
    original_config = json.loads(original_config_bytes)
    candidates = candidate_scripts(original_config)
    assert candidates, 'No JSON-parsing build generator script was created.'

    token = uuid.uuid4().hex[:12]
    target = f'generated_{token}'
    source = f'source_{token}.sh'
    synthetic = json.loads(original_config_bytes)
    synthetic['targets'][target] = {
        'lang': 'bash', 'src': source, 'deps': ['fetch_data']
    }
    source_path = PROJECT_DIR / source
    source_path.write_text('#!/bin/bash\necho generated\n')
    source_path.chmod(0o755)
    successful_command = None

    try:
        for candidate in candidates:
            for command in commands_for(candidate):
                CONFIG_PATH.write_text(json.dumps(synthetic, indent=2) + '\n')
                if MAKEFILE_PATH.exists():
                    MAKEFILE_PATH.unlink()
                if CI_YML_PATH.exists():
                    CI_YML_PATH.unlink()
                try:
                    result = subprocess.run(
                        command, cwd=PROJECT_DIR, text=True, capture_output=True, timeout=20
                    )
                    if result.returncode != 0:
                        continue
                    validate_makefile(synthetic)
                    validate_ci()
                    run_make_and_validate(synthetic, target)
                    successful_command = command
                    break
                except (AssertionError, subprocess.SubprocessError, OSError):
                    continue
            if successful_command:
                break
        assert successful_command is not None, \
            'No created script parsed a changed build_config.json and regenerated both valid artifacts.'
    finally:
        CONFIG_PATH.write_bytes(original_config_bytes)
        if source_path.exists():
            source_path.unlink()
        generated_path = PROJECT_DIR / target
        if generated_path.exists():
            generated_path.unlink()
        restored = False
        if successful_command is not None:
            try:
                result = subprocess.run(
                    successful_command, cwd=PROJECT_DIR, text=True, capture_output=True, timeout=20
                )
                restored = result.returncode == 0
            except (subprocess.SubprocessError, OSError):
                pass
        if not restored:
            MAKEFILE_PATH.write_bytes(original_makefile)
            CI_YML_PATH.parent.mkdir(parents=True, exist_ok=True)
            CI_YML_PATH.write_bytes(original_ci)

    validate_makefile(original_config)
    validate_ci()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
