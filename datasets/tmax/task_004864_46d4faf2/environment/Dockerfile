FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:0ee4e2eca7dc
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
