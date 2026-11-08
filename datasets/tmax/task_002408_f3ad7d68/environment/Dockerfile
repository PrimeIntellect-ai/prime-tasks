FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:b47b3d7f93bc
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
