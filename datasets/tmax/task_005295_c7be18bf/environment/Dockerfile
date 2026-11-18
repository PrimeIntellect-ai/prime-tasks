FROM --platform=linux/amd64 hamishivi/swerl-tmax-hardened:task_005295_c7be18bf-0c4e432c
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
