FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:e007b2da602d
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
