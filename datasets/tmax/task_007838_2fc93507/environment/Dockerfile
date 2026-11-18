FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:b3ae15634358
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
