FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:86d0c305828a
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
