FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:034cc8831ec4
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
