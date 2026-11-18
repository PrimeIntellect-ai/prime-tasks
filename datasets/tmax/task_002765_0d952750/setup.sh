#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/data /home/user/etl /home/user/output

    cat << 'EOF' > /home/user/data/kg_triples.tsv
Source_Node	Relationship_Type	Target_Node
API_Gateway	depends_on	Auth_Service
API_Gateway	depends_on	Data_Ingestor
API_Gateway	related_to	Metrics_Dashboard
Auth_Service	depends_on	User_DB
Data_Ingestor	depends_on	Message_Queue
Message_Queue	depends_on	Processing_Node
Processing_Node	depends_on	Storage_Cluster_9
Message_Queue	part_of	Infrastructure
User_DB	part_of	Infrastructure
Processing_Node	related_to	Metrics_Dashboard
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
