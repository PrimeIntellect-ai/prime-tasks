FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:0d2dc04c2ed2
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
