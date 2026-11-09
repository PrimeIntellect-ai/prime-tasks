FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:3c27d558f4ae
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
