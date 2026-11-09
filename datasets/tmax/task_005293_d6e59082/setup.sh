#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sudo postgresql postgresql-client
    pip3 install pytest flask fastapi uvicorn scikit-learn psycopg2-binary pandas requests

    mkdir -p /app

    cat << 'EOF' > /app/stats.csv
dataset_id,downloads
1,100000
2,50000
3,200000
4,80000
EOF

    cat << 'EOF' > /app/setup_db.sh
#!/bin/bash
/etc/init.d/postgresql start
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'postgres';"
sudo -u postgres createdb catalog
sudo -u postgres psql -d catalog -c "CREATE TABLE datasets (id INTEGER, name TEXT, description TEXT);"
sudo -u postgres psql -d catalog -c "INSERT INTO datasets (id, name, description) VALUES (1, 'ImageNet', 'A large visual database designed for use in visual object recognition software research.');"
sudo -u postgres psql -d catalog -c "INSERT INTO datasets (id, name, description) VALUES (2, 'Titanic', 'Machine learning dataset for predicting survival of passengers on the Titanic.');"
sudo -u postgres psql -d catalog -c "INSERT INTO datasets (id, name, description) VALUES (3, 'MNIST', 'A large database of handwritten digits commonly used for training various image processing systems.');"
sudo -u postgres psql -d catalog -c "INSERT INTO datasets (id, name, description) VALUES (4, 'COCO', 'Common Objects in Context is a large-scale object detection, segmentation, and captioning dataset.');"
EOF
    chmod +x /app/setup_db.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
