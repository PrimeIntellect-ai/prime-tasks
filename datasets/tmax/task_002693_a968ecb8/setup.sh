#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk coreutils sed grep
    pip3 install pytest

    mkdir -p /home/user/logs
    cd /home/user

    # Create data.txt
    gawk 'BEGIN {
        srand(42);
        for(i=1; i<=100; i++) {
            if(i==74) print "-42.5";
            else print rand() * 100;
        }
    }' > /home/user/data.txt

    # Create generator.log
    gawk 'BEGIN {
        srand(42);
        t = 1700000000;
        for(i=1; i<=100; i++) {
            t += int(rand()*5) + 1;
            time_str = strftime("%Y-%m-%d %H:%M:%S", t);
            if(i==74) val = "-42.5";
            else val = rand() * 100;
            printf "[%s] Generated value: %s\n", time_str, val;
        }
    }' > /home/user/logs/generator.log

    # Create processor.sh
    cat << 'EOF' > /home/user/processor.sh
#!/bin/bash
> /home/user/output.txt
> /home/user/logs/processor.log
while read -r val; do
    TIME=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$TIME] Processing $val" >> /home/user/logs/processor.log

    # Bug: no check for negative numbers
    res=$(bc -l <<< "
        x = $val;
        guess = x / 2.0;
        if(guess == 0) guess = 1;
        for(i=0; i<20; i++) {
            guess = 0.5 * (guess + x / guess);
        }
        guess;
    " 2>&1)

    # Check if bc outputted a valid number or failed
    if [[ -z "$res" ]] || [[ "$res" == *"runtime error"* ]]; then
        echo "[$TIME] FATAL: Convergence failure or math error on $val" >> /home/user/logs/processor.log
        exit 1
    fi
    echo "$res" >> /home/user/output.txt
done < /home/user/data.txt
EOF
    chmod +x /home/user/processor.sh

    # Create build.sh
    cat << 'EOF' > /home/user/build.sh
#!/bin/bash
echo "Starting build..."
/home/user/processor.sh
if [ $? -ne 0 ]; then
    echo "Build FAILED."
    exit 1
fi
echo "Build SUCCEEDED."
EOF
    chmod +x /home/user/build.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
