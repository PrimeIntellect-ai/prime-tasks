FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:28ea138c10d7
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
