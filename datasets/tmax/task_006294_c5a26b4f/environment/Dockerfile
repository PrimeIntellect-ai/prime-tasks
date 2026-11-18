FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:f4dd8519b30f
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
