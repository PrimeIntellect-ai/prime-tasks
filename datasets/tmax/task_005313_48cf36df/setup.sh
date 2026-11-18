#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git bc
pip3 install pytest

mkdir -p /home/user/math_repo
cd /home/user/math_repo
git init
git config user.name "Dev"
git config user.email "dev@example.com"

cat << 'EOF' > calc_integral.sh
#!/bin/bash
STEPS=1000
A=0
B=10

# Calculate using the trapezoidal rule: area += (f(x1) + f(x2)) / 2 * dx
echo "scale=4; sum=0; dx=($B-$A)/$STEPS; for(i=0; i<$STEPS; i++) { x1=$A+i*dx; x2=$A+(i+1)*dx; y1=3*x1^2; y2=3*x2^2; sum+=((y1+y2)/2)*dx; }; sum" | bc
EOF

chmod +x calc_integral.sh
git add calc_integral.sh
git commit -m "Initial commit - correct math"
git tag v1.0

# Create 200 commits
for i in $(seq 1 200); do
    if [ $i -eq 137 ]; then
        # Introduce the bug: forget to divide by 2 in the trapezoidal rule
        cat << 'EOF' > calc_integral.sh
#!/bin/bash
STEPS=1000
A=0
B=10

# Calculate using the trapezoidal rule: area += (f(x1) + f(x2)) / 2 * dx
echo "scale=4; sum=0; dx=($B-$A)/$STEPS; for(i=0; i<$STEPS; i++) { x1=$A+i*dx; x2=$A+(i+1)*dx; y1=3*x1^2; y2=3*x2^2; sum+=((y1+y2))*dx; }; sum" | bc
EOF
        git add calc_integral.sh
        git commit -m "Refactor integration loop $i"
    else
        echo "# Comment $i" >> calc_integral.sh
        git add calc_integral.sh
        git commit -m "Add comment $i"
    fi
done

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
