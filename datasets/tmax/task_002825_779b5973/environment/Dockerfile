FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:d8d61061b80a
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
