FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:f1fae8be2c8e
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
