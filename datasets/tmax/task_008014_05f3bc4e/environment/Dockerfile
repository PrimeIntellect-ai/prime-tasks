FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:a0e7af7c8214
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
