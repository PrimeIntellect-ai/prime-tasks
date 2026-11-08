FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:03f1f46f2827
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
