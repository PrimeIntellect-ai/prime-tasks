FROM --platform=linux/amd64 hamishivi/swerl-tmax-hardened:task_001632_2775f42b-0c4e432c
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
