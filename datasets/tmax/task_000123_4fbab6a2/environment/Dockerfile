FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:65f98c2c33a5
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
