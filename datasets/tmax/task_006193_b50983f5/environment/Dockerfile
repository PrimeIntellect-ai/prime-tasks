FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:be153f4c1ea7
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
