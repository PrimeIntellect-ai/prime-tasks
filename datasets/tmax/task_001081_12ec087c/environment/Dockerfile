FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:689996e5d8e1
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
