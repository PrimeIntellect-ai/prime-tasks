FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:9e6cb9cfda91
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
