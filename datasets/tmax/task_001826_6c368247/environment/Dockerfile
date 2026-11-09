FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:53b8e2a1d594
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
