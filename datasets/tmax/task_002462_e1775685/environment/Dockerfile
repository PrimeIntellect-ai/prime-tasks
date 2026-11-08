FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:2ddc3c3ae1d8
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
