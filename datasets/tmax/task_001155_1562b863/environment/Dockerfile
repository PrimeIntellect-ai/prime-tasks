FROM --platform=linux/amd64 hamishivi/swerl-tmax-hardened:task_001155_1562b863-0c4e432c
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
