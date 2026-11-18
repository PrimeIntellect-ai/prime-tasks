FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:d5c296422c5a
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
