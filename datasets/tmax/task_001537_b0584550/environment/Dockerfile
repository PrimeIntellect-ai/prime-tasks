FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:4bb851d49b4a
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
