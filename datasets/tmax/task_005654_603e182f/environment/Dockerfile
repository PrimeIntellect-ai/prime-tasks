FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:5c8020ff7d8b
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
