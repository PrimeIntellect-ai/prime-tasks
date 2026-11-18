#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq gawk
    pip3 install pytest

    mkdir -p /home/user/project/downloads
    cd /home/user/project

    # Create app.json
    cat << 'EOF' > app.json
{
  "dependencies": {
    "core_logger": ">=1.0.0",
    "http_client": ">=2.0.0"
  }
}
EOF

    # Create dummy tarballs and calculate sha256 for registry
    create_plugin() {
        local name=$1
        local version=$2
        local content=$3
        local corrupt=$4
        local filename="downloads/${name}-${version}.tar.gz"

        echo "$content" > "/tmp/dummy_file_${name}_${version}.txt"
        tar -czf "$filename" -C /tmp "dummy_file_${name}_${version}.txt"

        local real_sha=$(sha256sum "$filename" | awk '{print $1}')

        if [ "$corrupt" = "true" ]; then
            echo "badbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadbadb"
        else
            echo "$real_sha"
        fi
    }

    # core_logger
    sha_cl_1_0_0=$(create_plugin core_logger 1.0.0 "logger 1.0.0" false)
    sha_cl_1_2_0=$(create_plugin core_logger 1.2.0 "logger 1.2.0" false)
    sha_cl_1_5_0=$(create_plugin core_logger 1.5.0 "logger 1.5.0" true) # Corrupt checksum in registry

    # http_client
    sha_hc_2_0_0=$(create_plugin http_client 2.0.0 "http 2.0.0" false)
    sha_hc_2_1_0=$(create_plugin http_client 2.1.0 "http 2.1.0" false)

    # network_utils (dependency of http_client)
    sha_nu_1_0_0=$(create_plugin network_utils 1.0.0 "net 1.0.0" false)
    sha_nu_1_1_0=$(create_plugin network_utils 1.1.0 "net 1.1.0" false)
    sha_nu_1_2_0=$(create_plugin network_utils 1.2.0 "net 1.2.0" false)

    # Create registry.csv
    cat << EOF > registry.csv
core_logger,1.0.0,NONE,$sha_cl_1_0_0
core_logger,1.2.0,NONE,$sha_cl_1_2_0
core_logger,1.5.0,NONE,$sha_cl_1_5_0
http_client,2.0.0,network_utils>=1.0.0,$sha_hc_2_0_0
http_client,2.1.0,network_utils>=1.1.0,$sha_hc_2_1_0
network_utils,1.0.0,NONE,$sha_nu_1_0_0
network_utils,1.1.0,core_logger>=1.2.0,$sha_nu_1_1_0
network_utils,1.2.0,core_logger>=1.5.0,$sha_nu_1_2_0
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
