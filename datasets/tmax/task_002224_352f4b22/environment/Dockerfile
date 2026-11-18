FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:6230c9b2d61d
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
