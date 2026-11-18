FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:6bcb48b8e8a9
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
