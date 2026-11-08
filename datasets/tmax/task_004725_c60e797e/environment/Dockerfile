FROM --platform=linux/amd64 hamishivi/swerl-tmax-hardened:task_004725_c60e797e-0c4e432c
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
