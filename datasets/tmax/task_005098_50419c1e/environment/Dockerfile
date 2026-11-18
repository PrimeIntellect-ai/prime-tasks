FROM --platform=linux/amd64 hamishivi/swerl-tmax-hardened:task_005098_50419c1e-0c4e432c
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
