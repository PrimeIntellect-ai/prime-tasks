FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:cad7f9c27b3f
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
