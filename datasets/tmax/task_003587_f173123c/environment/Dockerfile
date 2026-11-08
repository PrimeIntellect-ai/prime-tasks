FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:f7d7da7d71d3
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
