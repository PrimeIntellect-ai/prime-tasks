FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:bf12f2de9d8f
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
