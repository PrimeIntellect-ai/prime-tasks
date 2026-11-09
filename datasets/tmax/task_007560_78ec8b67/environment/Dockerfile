FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:f7b0e6b0c81a
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
