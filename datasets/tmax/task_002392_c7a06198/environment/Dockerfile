FROM --platform=linux/amd64 hamishivi/swerl-tmax-hardened:task_002392_c7a06198-0c4e432c
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
