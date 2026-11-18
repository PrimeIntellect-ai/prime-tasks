FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:4f9a1568e5de
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
