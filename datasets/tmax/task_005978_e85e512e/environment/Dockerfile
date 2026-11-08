FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:cdc4e2ca7776
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
