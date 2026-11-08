#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rsync cron
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /tmp/remote_drop
    mkdir -p /home/user/processing_data

    cat << 'EOF' > /home/user/target_profile.txt
Apache Kafka is a distributed event store and stream-processing platform. It is designed to handle real-time data feeds with high throughput.
EOF

    cat << 'EOF' > /tmp/remote_drop/doc1.txt
Apache Spark is a unified analytics engine for large-scale data processing. It provides high-level APIs in Java, Scala, Python and R.
EOF

    cat << 'EOF' > /tmp/remote_drop/doc2.txt
RabbitMQ is an open-source message-broker software that originally implemented the Advanced Message Queuing Protocol and has since been extended.
EOF

    cat << 'EOF' > /tmp/remote_drop/doc3.txt
A distributed streaming platform like Kafka is designed for high throughput event processing and real time data feeds. Stream processing is key.
EOF

    chmod -R 777 /home/user
    chmod -R 777 /tmp/remote_drop
