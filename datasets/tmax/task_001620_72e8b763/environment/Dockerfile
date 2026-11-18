FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:0bfb3f3b5e7a
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
