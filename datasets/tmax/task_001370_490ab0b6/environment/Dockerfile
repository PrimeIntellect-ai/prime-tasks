FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:05f51e8e3f18
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
