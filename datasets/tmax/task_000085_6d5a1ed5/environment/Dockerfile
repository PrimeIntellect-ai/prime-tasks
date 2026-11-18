FROM --platform=linux/amd64 hamishivi/swerl-tmax-hardened:task_000085_6d5a1ed5-0c4e432c
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
