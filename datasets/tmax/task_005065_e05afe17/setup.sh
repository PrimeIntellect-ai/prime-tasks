#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages for the task
    apt-get install -y imagemagick tesseract-ocr g++ nlohmann-json3-dev expect

    # Create directories
    mkdir -p /app/corpus/clean /app/corpus/evil /app/corpus/raw

    # Generate policy image
    convert -size 800x200 xc:white -pointsize 24 -fill black -annotate +10+50 "MANDATORY TAG REQUIREMENT: 'CostCenter=FinOps'" /app/policy.png

    # Generate JSON files
    for i in $(seq 1 10); do
        echo '{"tags": ["Env=Prod", "CostCenter=FinOps"]}' > /app/corpus/clean/file_$i.json
        echo '{"tags": ["Env=Prod", "CostCenter=R&D"]}' > /app/corpus/evil/file_$i.json
        echo '{"tags": ["Env=Prod", "CostCenter=FinOps"]}' > /app/corpus/raw/clean_$i.json
        echo '{"tags": ["Env=Prod", "CostCenter=R&D"]}' > /app/corpus/raw/evil_$i.json
    done

    # Create fake deployer
    cat << 'EOF' > /app/fake_deployer
#!/bin/bash
DIR=$1
COUNT=$(ls -1 "$DIR" 2>/dev/null | wc -l)
echo -n "Are you sure you want to deploy $COUNT files? (y/n): "
read ans
if [ "$ans" = "y" ]; then
    exit 0
else
    exit 1
fi
EOF
    chmod +x /app/fake_deployer

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
