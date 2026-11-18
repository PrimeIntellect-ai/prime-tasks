FROM --platform=linux/amd64 hamishivi/swerl-tmax-hardened:task_001372_52718284-0c4e432c
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
