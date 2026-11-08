FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:7ca1fd7b0b8d
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
