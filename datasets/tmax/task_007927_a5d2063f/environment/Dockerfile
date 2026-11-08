FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:6d6b3c001925
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
