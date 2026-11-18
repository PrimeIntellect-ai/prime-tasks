FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:00a5e3c30a9a
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
