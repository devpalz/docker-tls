#!/bin/bash
set -eux

# Location where the Root CA ket/cert is located, as we need to sign our client certificates with the root CA
DOCKER_HOST_SSL_HOME="/etc/docker/ssl"

# Location to generate client certificates
DOCKER_CLIENT_SSL_HOME="/etc/docker/ssl/client"

# Create directories for storing client ssl certificates
mkdir --parent "$DOCKER_CLIENT_SSL_HOME"

echo "Creating a Private Key for the Client"
sudo openssl genrsa -out "${DOCKER_CLIENT_SSL_HOME}/client-key.pem" 4096


echo "Creating a Client Certificate Signing Request"
sudo openssl req -subj '/CN=client' \
                 -new \
                 -key "$DOCKER_CLIENT_SSL_HOME/client-key.pem" \
                 -out "$DOCKER_CLIENT_SSL_HOME/client.csr"


# add client info to extfile.cnf
cat <<EOF > "$DOCKER_CLIENT_SSL_HOME/extfile.cnf"
subjectAltName = DNS:localhost,IP:127.0.0.1
extendedKeyUsage = serverAuth
extendedKeyUsage = clientAuth
EOF

# create client certificate
sudo openssl x509 -req \
                  -days 365 \
                  -in "$DOCKER_CLIENT_SSL_HOME/client.csr" \
                  -CA "$DOCKER_HOST_SSL_HOME/ca.pem" \
                  -CAkey "$DOCKER_HOST_SSL_HOME/ca-key.pem" \
                  -CAcreateserial \
                  -out "$DOCKER_CLIENT_SSL_HOME/client-cert.pem" \
                  -extfile "$DOCKER_CLIENT_SSL_HOME/extfile.cnf"

echo "Removing OpenSSL Extention Files and Certificate Signing Request"
sudo rm "$DOCKER_CLIENT_SSL_HOME/extfile.cnf" "$DOCKER_CLIENT_SSL_HOME/client.csr"

echo "Making Certificate World Readable"
sudo chmod -v 0444 "$DOCKER_CLIENT_SSL_HOME/client-cert.pem"

echo "Attempting to access with tls!"
docker --tlsverify \
            --tlscacert="$DOCKER_HOST_SSL_HOME/ca.pem" \
            --tlscert="$DOCKER_CLIENT_SSL_HOME/client-cert.pem" \
            --tlskey="$DOCKER_CLIENT_SSL_HOME/client-key.pem" \
            -H=127.0.0.1:2376 \
            version

ls -al "$DOCKER_CLIENT_SSL_HOME"
