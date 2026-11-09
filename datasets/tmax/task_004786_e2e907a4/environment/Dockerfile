FROM --platform=linux/amd64 hamishivi/swerl-tmax-hardened:task_004786_e2e907a4-0c4e432c
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
