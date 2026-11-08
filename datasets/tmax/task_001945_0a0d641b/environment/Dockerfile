FROM --platform=linux/amd64 hamishi740/swerl-tmax-v3:3846e710b8c8
USER root
RUN mkdir -p /workspace /output /logs/verifier /root && ([ -d /app ] || ln -sf /workspace /app)
WORKDIR /app
