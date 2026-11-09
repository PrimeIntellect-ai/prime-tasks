FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:0850fe3d015d
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
