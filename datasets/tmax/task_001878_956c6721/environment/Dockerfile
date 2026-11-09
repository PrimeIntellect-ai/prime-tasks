FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:b0dea22d6ebf
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
