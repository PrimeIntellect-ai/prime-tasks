FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:d80b4d03d1da
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
