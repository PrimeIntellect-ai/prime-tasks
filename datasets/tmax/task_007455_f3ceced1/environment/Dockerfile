FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:3d8e2da1a7bc
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
