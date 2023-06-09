FROM debian:bullseye AS downloader

WORKDIR /deps

RUN apt-get update && apt-get install curl -y

RUN curl -L -o /deps/cfssl https://github.com/cloudflare/cfssl/releases/download/v1.4.1/cfssl_1.4.1_linux_amd64 && \
  curl -L -o /deps/cfssljson https://github.com/cloudflare/cfssl/releases/download/v1.4.1/cfssljson_1.4.1_linux_amd64 && \
  chmod +x /deps/cfssl && chmod +x /deps/cfssljson && \
  curl -L -o /deps/astartectl_22.11.02_linux_x86_64.tar.gz https://github.com/astarte-platform/astartectl/releases/download/v22.11.02/astartectl_22.11.02_linux_x86_64.tar.gz && \
  tar xf /deps/astartectl_22.11.02_linux_x86_64.tar.gz && \
  chmod +x /deps/astartectl

FROM debian:bullseye-slim

RUN apt-get update && apt-get install openssl -y && apt-get clean autoclean && \
  apt-get autoremove --yes && rm -rf /var/lib/{apt,dpkg,cache,log}/

COPY --from=downloader deps/* /usr/local/bin/

COPY generate-compose-files.sh /usr/local/bin/generate-compose-files.sh

RUN chmod +x /usr/local/bin/generate-compose-files.sh

VOLUME /compose

ENTRYPOINT ["/usr/local/bin/generate-compose-files.sh"]
