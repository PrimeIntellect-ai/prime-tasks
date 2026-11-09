FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:7947e907c6b6
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
