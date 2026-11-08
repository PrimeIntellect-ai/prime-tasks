FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:5b7f97f83c4a
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
