FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:8e6e2d56e00a
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
