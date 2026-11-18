FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:6a9a4e5d2c4d
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
