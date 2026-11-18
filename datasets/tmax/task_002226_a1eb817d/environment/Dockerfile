FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:c42c05a55a1f
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
