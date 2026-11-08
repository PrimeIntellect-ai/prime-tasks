FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:48e9d01db03d
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
