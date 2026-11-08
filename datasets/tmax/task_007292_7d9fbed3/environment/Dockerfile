FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:225ba52d700a
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
