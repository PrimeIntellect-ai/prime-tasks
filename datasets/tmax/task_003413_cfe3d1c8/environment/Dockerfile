FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:3d0d1f35b0e6
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
