FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:40d9f8d36c83
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
