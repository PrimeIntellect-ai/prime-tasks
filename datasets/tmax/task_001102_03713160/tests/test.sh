#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import tarfile


def test_rotated_configs_tarball():
    tarball_path = "/home/user/rotated_configs.tar.gz"
    assert os.path.exists(tarball_path), f"Tarball {tarball_path} does not exist."
    assert tarfile.is_tarfile(tarball_path), f"{tarball_path} is not a valid tar file."

    # Expected results are fixed from the original task inputs, not from the
    # agent-writable current state of /home/user/configs.
    expected_files = {
        "app_beta_v3.xml": b"<config><version>3</version><setting>B</setting></config>\n",
        "app_epsilon_v4.xml": b"<config><version>4</version><setting>E</setting></config>\n",
    }

    try:
        with tarfile.open(tarball_path, "r:gz") as tar:
            members = tar.getmembers()

            # The files should be placed at the root of the archive.
            member_names = [m.name.lstrip('./') for m in members if m.isfile()]

            assert set(member_names) == set(expected_files.keys()), \
                f"Expected files in tarball: {sorted(expected_files.keys())}, but found: {sorted(member_names)}"

            for member in members:
                if not member.isfile():
                    continue

                normalized_name = member.name.lstrip('./')
                f = tar.extractfile(member)
                assert f is not None, f"Could not extract {member.name} from tarball."
                content = f.read()
                assert content == expected_files[normalized_name], \
                    f"Content of {member.name} in tarball does not match the original config.xml."
    except tarfile.ReadError:
        assert False, f"{tarball_path} is not a valid gzip-compressed tar archive."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
