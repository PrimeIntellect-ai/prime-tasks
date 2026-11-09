FROM --platform=linux/amd64 hamishivi/swerl-tmax-hardened:task_000378_d39c7697-0c4e432c
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
