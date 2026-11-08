#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import subprocess
import uuid
import yaml


def parse_manifest(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    name_match = re.search(r'name:\s*([^\s]+)', content)
    name = name_match.group(1) if name_match else ''

    image_match = re.search(r'image:\s*([^\s]+)', content)
    image = image_match.group(1) if image_match else ''

    ports = []
    ports_section = re.search(r'ports:(.*?)(?:mounts:|EOF|\Z)', content, re.DOTALL)
    if ports_section:
        port_blocks = re.findall(r'-\s*port:\s*(\d+)\s*protocol:\s*([^\s]+)', ports_section.group(1))
        for p, proto in port_blocks:
            ports.append((p, proto))

    mounts = []
    mounts_section = re.search(r'mounts:(.*?)(?:EOF|\Z)', content, re.DOTALL)
    if mounts_section:
        mount_blocks = re.findall(r'-\s*source:\s*([^\s]+)\s*destination:\s*([^\s]+)\s*fstype:\s*([^\s]+)', mounts_section.group(1))
        for s, d, fs in mount_blocks:
            mounts.append((s, d, fs))

    return {
        'name': name,
        'image': image,
        'ports': ports,
        'mounts': mounts
    }


def get_expected_outputs():
    manifests_dir = '/home/user/manifests'
    services = []
    if os.path.isdir(manifests_dir):
        for fname in os.listdir(manifests_dir):
            if fname.endswith('.yaml'):
                services.append(parse_manifest(os.path.join(manifests_dir, fname)))

    services.sort(key=lambda x: x['name'])

    fstab = []
    firewall = []
    containers = []

    for svc in services:
        for s, d, fs in svc['mounts']:
            fstab.append(f"{s} {d} {fs} defaults 0 0")
        for p, proto in svc['ports']:
            firewall.append(f"iptables -A INPUT -p {proto} --dport {p} -j ACCEPT")
        if svc['name'] and svc['image']:
            containers.append(f"podman run -d --name {svc['name']} {svc['image']}")

    return '\n'.join(fstab), '\n'.join(firewall), '\n'.join(containers)


def test_fstab_content():
    expected_fstab, _, _ = get_expected_outputs()
    file_path = '/home/user/output/fstab.conf'
    assert os.path.isfile(file_path), f"File {file_path} does not exist."
    with open(file_path, 'r') as f:
        content = f.read().strip()
    assert content == expected_fstab.strip(), f"Content of {file_path} does not match the expected fstab format or order.\nExpected:\n{expected_fstab}\nGot:\n{content}"


def test_firewall_content():
    _, expected_firewall, _ = get_expected_outputs()
    file_path = '/home/user/output/firewall.sh'
    assert os.path.isfile(file_path), f"File {file_path} does not exist."
    with open(file_path, 'r') as f:
        content = f.read().strip()
    assert content == expected_firewall.strip(), f"Content of {file_path} does not match the expected firewall rules or order.\nExpected:\n{expected_firewall}\nGot:\n{content}"


def test_containers_content():
    _, _, expected_containers = get_expected_outputs()
    file_path = '/home/user/output/containers.sh'
    assert os.path.isfile(file_path), f"File {file_path} does not exist."
    with open(file_path, 'r') as f:
        content = f.read().strip()
    assert content == expected_containers.strip(), f"Content of {file_path} does not match the expected container commands or order.\nExpected:\n{expected_containers}\nGot:\n{content}"


def test_operator_processes_new_manifests(tmp_path):
    operator = '/home/user/operator.py'
    manifests_dir = '/home/user/manifests'
    output_dir = '/home/user/output'
    assert os.path.isfile(operator), f"File {operator} does not exist."

    manifests_backup = tmp_path / 'manifests_backup'
    output_backup = tmp_path / 'output_backup'
    shutil.copytree(manifests_dir, manifests_backup)
    shutil.copytree(output_dir, output_backup)

    token = uuid.uuid4().hex[:10]
    services = [
        {
            'apiVersion': 'v1',
            'kind': 'CustomService',
            'metadata': {'name': f'zebra-{token}'},
            'spec': {
                'image': f'registry.example/zebra:{token}',
                'ports': [
                    {'port': 21001, 'protocol': 'udp'},
                    {'port': 21002, 'protocol': 'tcp'},
                ],
                'mounts': [
                    {'source': f'/srv/{token}/z-first', 'destination': '/opt/z-first', 'fstype': 'xfs'},
                    {'source': f'/srv/{token}/z-second', 'destination': '/opt/z-second', 'fstype': 'ext4'},
                ],
            },
        },
        {
            'apiVersion': 'v1',
            'kind': 'CustomService',
            'metadata': {'name': f'alpha-{token}'},
            'spec': {
                'image': f'registry.example/alpha:{token}',
                'ports': [{'port': 22003, 'protocol': 'tcp'}],
                'mounts': [{'source': f'/srv/{token}/alpha', 'destination': '/data/alpha', 'fstype': 'btrfs'}],
            },
        },
        {
            'apiVersion': 'v1',
            'kind': 'CustomService',
            'metadata': {'name': f'middle-{token}'},
            'spec': {
                'image': f'registry.example/middle:{token}',
                'ports': [{'port': 23004, 'protocol': 'udp'}],
                'mounts': [{'source': f'/srv/{token}/middle', 'destination': '/data/middle', 'fstype': 'ext4'}],
            },
        },
    ]

    try:
        shutil.rmtree(manifests_dir)
        os.makedirs(manifests_dir)
        # Deliberately make filename order differ from service-name order.
        filenames = ['00-zebra.yaml', '99-alpha.yaml', '50-middle.yaml']
        for filename, service in zip(filenames, services):
            with open(os.path.join(manifests_dir, filename), 'w') as f:
                yaml.safe_dump(service, f, sort_keys=False)

        os.makedirs(output_dir, exist_ok=True)
        stale_path = os.path.join(output_dir, f'stale-{token}.txt')
        with open(stale_path, 'w') as f:
            f.write('must be removed')

        result = subprocess.run(
            ['python3', operator],
            cwd='/home/user',
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, f"operator.py failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        assert not os.path.exists(stale_path), 'operator did not clear an existing output file'

        ordered = sorted(services, key=lambda item: item['metadata']['name'])
        expected_fstab = []
        expected_firewall = []
        expected_containers = []
        for service in ordered:
            spec = service['spec']
            for mount in spec['mounts']:
                expected_fstab.append(
                    f"{mount['source']} {mount['destination']} {mount['fstype']} defaults 0 0"
                )
            for port in spec['ports']:
                expected_firewall.append(
                    f"iptables -A INPUT -p {port['protocol']} --dport {port['port']} -j ACCEPT"
                )
            expected_containers.append(
                f"podman run -d --name {service['metadata']['name']} {spec['image']}"
            )

        expected = {
            'fstab.conf': '\n'.join(expected_fstab),
            'firewall.sh': '\n'.join(expected_firewall),
            'containers.sh': '\n'.join(expected_containers),
        }
        assert set(os.listdir(output_dir)) == set(expected), 'output directory was not cleared or required files are missing'
        for filename, wanted in expected.items():
            path = os.path.join(output_dir, filename)
            assert os.path.isfile(path), f"File {path} does not exist after running operator.py"
            with open(path, 'r') as f:
                actual = f.read().strip()
            assert actual == wanted.strip(), f"Unexpected dynamic output in {path}\nExpected:\n{wanted}\nGot:\n{actual}"
    finally:
        shutil.rmtree(manifests_dir, ignore_errors=True)
        shutil.rmtree(output_dir, ignore_errors=True)
        shutil.copytree(manifests_backup, manifests_dir)
        shutil.copytree(output_backup, output_dir)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
