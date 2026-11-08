FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:ee8c7bb5b237
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
