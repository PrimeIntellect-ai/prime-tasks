FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:43eb0b9c57cf
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
