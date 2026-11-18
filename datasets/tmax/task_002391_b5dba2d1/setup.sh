#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required system packages
    apt-get install -y tesseract-ocr imagemagick gsfonts git expect cron locales

    # Generate required locale
    locale-gen de_DE.UTF-8

    # Create directories and initial files
    mkdir -p /app

    # Generate the image with the secret token
    convert -background white -fill black -font Courier -pointsize 24 label:"S3CR3T-AL3RT-T0K3N" /app/token.png

    # Create the interactive_submit.sh script
    cat << 'EOF' > /app/interactive_submit.sh
#!/bin/bash
read -p "Enter local repo path: " repo_path
read -p "Enter alert level: " level
read -p "Enter alert message: " message

cd "$repo_path" || exit 1
filename="alert_$(date +%s).alert"
echo "$level:$message" > "$filename"
git add "$filename"
git commit -m "Add alert $filename"
git push origin master
EOF
    chmod +x /app/interactive_submit.sh

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
