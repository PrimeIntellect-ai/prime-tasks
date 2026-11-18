FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:a46a93a1c1f3
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
