FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:efa2c5170cb5
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
