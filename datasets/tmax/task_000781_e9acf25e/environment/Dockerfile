FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:1061dd1962ca
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
