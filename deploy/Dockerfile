# syntax=docker/dockerfile:1
# The SecondTrust website: the static files in docs/, served by unprivileged nginx on port 8080.
# There are no RUN steps, so it builds for linux/arm64 (the Myprod nodes) and linux/amd64 without emulation.
# Build from the repository root:  docker buildx build -f deploy/Dockerfile .
FROM nginxinc/nginx-unprivileged:1.27-alpine@sha256:65e3e85dbaed8ba248841d9d58a899b6197106c23cb0ff1a132b7bfe0547e4c0
LABEL org.opencontainers.image.source="https://github.com/blackdragoon26/stressTestIt_beforeReturnWindowCloses" \
      org.opencontainers.image.description="SecondTrust website: static files served by unprivileged nginx" \
      org.opencontainers.image.licenses="NOASSERTION"
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY docs/ /usr/share/nginx/html/
EXPOSE 8080
