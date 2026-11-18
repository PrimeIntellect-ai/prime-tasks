#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/app/handlers/
    mkdir -p /home/user/app/public/uploads/

    # Create handler files
    cat << 'EOF' > /home/user/app/handlers/data_export.py
def export_data(cursor, user_id):
    cursor.execute("SELECT * FROM exports WHERE user_id = ?", (user_id,))
    return cursor.fetchall()
EOF

    cat << 'EOF' > /home/user/app/handlers/image_processor.py
def process_image(db_session, image_id):
    return db_session.query(Image).filter(Image.id == image_id).first()
EOF

    cat << 'EOF' > /home/user/app/handlers/report_generator.py
def generate_report(cursor, req_date):
    # VULNERABLE SQL INJECTION
    cursor.execute(f"SELECT * FROM reports WHERE date = '{req_date}'")
    return cursor.fetchall()
EOF

    cat << 'EOF' > /home/user/app/handlers/session_manager.py
def get_session(cursor, token):
    cursor.execute("SELECT * FROM sessions WHERE token = %s", [token])
    return cursor.fetchone()
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
