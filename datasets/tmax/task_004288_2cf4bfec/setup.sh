#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick ffmpeg tesseract-ocr
    pip3 install pytest

    mkdir -p /app

    # Create the video file
    convert -size 1920x1080 xc:black -font DejaVu-Sans -pointsize 48 -fill white -draw "text 100,100 'BACKUP SPECIFICATION v2.1\n=========================\nBASE_MTIME=1700000000\nEXCLUDE=*.tmp\nEXCLUDE=cache/\nEXCLUDE=/var/log'" frame.png
    ffmpeg -loop 1 -i frame.png -c:v libx264 -t 5 -pix_fmt yuv420p /app/backup_spec.mp4
    rm frame.png

    # Create the oracle planner
    cat << 'EOF' > /app/oracle_planner
#!/usr/bin/env python3
import sys, json, fnmatch

def match_exclude(path):
    excludes = ["*.tmp", "*cache/*", "/var/log*"]
    for exc in excludes:
        if fnmatch.fnmatch(path, exc): return True
    return False

def main():
    try:
        data = json.load(sys.stdin)
    except:
        return

    nodes = {d['path']: d for d in data}
    roots = []
    for p in nodes:
        parent = '/'.join(p.rstrip('/').split('/')[:-1])
        if not parent: parent = '/'
        if parent not in nodes and p != '/':
            roots.append(p)
    roots.sort()

    stack = set()

    def dfs(curr_path, logical_path):
        if logical_path in stack:
            return
        stack.add(logical_path)

        node = nodes.get(curr_path)
        if not node or match_exclude(logical_path):
            stack.remove(logical_path)
            return

        if node['type'] == 'file':
            if node.get('mtime', 0) > 1700000000:
                print(f"{logical_path},{node['mtime']}")
        elif node['type'] == 'symlink':
            dfs(node.get('target'), logical_path)
        elif node['type'] == 'directory':
            children = [p for p in nodes if p.startswith(curr_path + '/') and p.count('/') == curr_path.count('/') + 1]
            children.sort()
            for child in children:
                child_name = child.split('/')[-1]
                dfs(child, logical_path + '/' + child_name if logical_path != '/' else '/' + child_name)

        stack.remove(logical_path)

    for r in roots:
        dfs(r, r)

if __name__ == '__main__':
    main()
EOF
    chmod +x /app/oracle_planner

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
