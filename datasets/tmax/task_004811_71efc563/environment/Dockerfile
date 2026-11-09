FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:b2526f401870
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
