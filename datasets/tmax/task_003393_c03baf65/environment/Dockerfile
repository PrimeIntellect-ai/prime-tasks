FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:3e0ba4f6fa9f
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
