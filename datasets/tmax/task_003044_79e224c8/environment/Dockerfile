FROM --platform=linux/amd64 hamishivi/swerl-tmax-hardened:task_003044_79e224c8-0c4e432c
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
