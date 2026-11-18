#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq zip unzip tar
    pip3 install pytest

    mkdir -p /home/user/incoming
    cd /home/user/incoming

    cat << 'EOF' > alpha_release.meta
<artifact>
  <name>AlphaTools</name>
  <version>2.1</version>
  <arch>arm64</arch>
  <status>production</status>
</artifact>
EOF
    echo "ID=alpha-992" > build.txt
    tar -czf alpha_release.tar.gz build.txt
    rm build.txt

    cat << 'EOF' > beta_snapshot.meta
<artifact>
  <name>BetaApp</name>
  <version>1.0</version>
  <arch>x86_64</arch>
  <status>testing</status>
</artifact>
EOF
    echo "ID=beta-001" > build.txt
    zip -q beta_snapshot.zip build.txt
    rm build.txt

    cat << 'EOF' > gamma_core.meta
<artifact>
  <name>GammaCore</name>
  <version>3.0.1</version>
  <arch>x86_64</arch>
  <status>production</status>
</artifact>
EOF
    echo "ID=gamma-777" > build.txt
    zip -q gamma_core.zip build.txt
    rm build.txt

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/incoming
    chmod -R 777 /home/user
