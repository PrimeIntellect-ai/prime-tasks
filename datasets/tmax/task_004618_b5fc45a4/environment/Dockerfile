FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:acba4f6f4841
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
