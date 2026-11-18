FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:602b5954e10f
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
