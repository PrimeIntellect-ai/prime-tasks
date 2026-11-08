FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:f3c9c93e9ba5
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
