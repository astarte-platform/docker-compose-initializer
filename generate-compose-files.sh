#!/usr/bin/env bash

set -eEuo pipefail

# Trap -e errors
trap 'echo "Exit status $? at line $LINENO from: $BASH_COMMAND"' ERR

# Generate keys if necessary
if [ ! -f /compose/cfssl-config/ca.pem ] || [ ! -f /compose/cfssl-config/ca-key.pem ]; then
    mkdir -p /compose/cfssl-config/
    pushd /compose/cfssl-config/

    cfssl gencert -initca "csr_root_ca.json" | cfssljson -bare ca

    popd
fi

# Generate housekeeping keypairs
if [ ! -f /compose/astarte-keys/housekeeping_public.pem ]; then
    mkdir -p /compose/astarte-keys
    pushd /compose/astarte-keys/

    astartectl utils gen-keypair housekeeping

    popd
fi

# Generate TLS CA and certificates
dir=/compose/certificates
san_yaml='[SAN]
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = astarte.localhost
DNS.2 = *.astarte.localhost
DNS.3 = edgehog.localhost
DNS.4 = *.edgehog.localhost

[req]
req_extensions = v3_req
'

mkdir -p $dir

if [[ ! -f $dir/ca.key ]]; then
    openssl ecparam -name secp384r1 -genkey -out $dir/ca.key -noout
fi

if [[ ! -f $dir/ca.csr ]]; then
    openssl req -new \
        -key $dir/ca.key \
        -out $dir/ca.csr \
        -subj "/C=IT/O=Astarte Internal/CN=Astarte Root CA"
fi

if [[ ! -f $dir/ca.crt ]]; then
    openssl x509 -req \
        -in $dir/ca.csr \
        -out $dir/ca.crt \
        -signkey $dir/ca.key \
        -days 3650 -sha256 \
        -extfile <(printf "basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\n")
fi

if [[ ! -f $dir/tls.key ]]; then
    openssl ecparam -name secp384r1 -genkey -noout -out $dir/tls.key

    openssl req -new -key $dir/tls.key -out $dir/tls.csr \
        -subj "/C=IT/O=Astarte Internal/CN=api.astarte.localhost"

    openssl x509 -req -in $dir/tls.csr -out $dir/tls.crt -CA $dir/ca.crt -CAkey $dir/ca.key -days 3650 \
        -extensions v3_req \
        -extensions SAN \
        -extfile <(cat /etc/ssl/openssl.cnf <(printf "%s" "$san_yaml"))

    openssl verify -CAfile $dir/ca.crt $dir/tls.crt

    openssl x509 -in $dir/tls.crt -inform pem -noout -text
fi

# Generate self-signed VerneMQ certificate if necessary
if [ ! -f /compose/vernemq-certs/cert ]; then
    mkdir -p /compose/vernemq-certs/
    pushd /compose/vernemq-certs/

    mkdir -p ca/certs ca/crl ca/newcerts ca/private

    # Structure
    touch ca/index.txt
    touch ca/index.txt.attr
    echo 1000 >ca/serial

    cp -v $dir/tls.key privkey
    cp -v $dir/tls.crt server.crt

    # Generate VMQ-friendly certificate with the whole chain
    cat server.crt $dir/ca.crt >cert

    popd
fi
