FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:ca3a509075ec
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
