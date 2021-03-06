#!/bin/bash
set -eu

# Location to generate the host Certificate
DOCKER_HOST_SSL_HOME="/etc/docker/ssl"

# Location to generate client certificates
DOCKER_CLIENT_SSL_HOME="/etc/docker/ssl"



# Create directories for storing ssl certificates
mkdir --parent "$DOCKER_CLIENT_SSL_HOME"
sudo mkdir --parent "$DOCKER_HOST_SSL_HOME"


# First we need to create a CA to sign our certificates
echo "Creating a Root Key"
sudo openssl genrsa -out "$DOCKER_HOST_SSL_HOME/ca-key.pem" 4096

echo "Creating root certificate"
sudo openssl req -new \
     -x509 \
     -days 365 \
     -key "$DOCKER_HOST_SSL_HOME/ca-key.pem" \
     -subj "/CN=MyRootCA/O=MyOrganisation/C=UK" \
     -out "$DOCKER_HOST_SSL_HOME/ca.pem"



echo "Creating Docker Host Private Key"
sudo openssl genrsa -out "$DOCKER_HOST_SSL_HOME/server-key.pem" 4096

echo "Creating the Server's Certificate Signing Request"
sudo openssl req -subj "/CN=localhost" -new -key $DOCKER_HOST_SSL_HOME/server-key.pem -out $DOCKER_HOST_SSL_HOME/server.csr

sudo cat <<EOF > "$DOCKER_HOST_SSL_HOME/server-extfile.cnf"
subjectAltName = DNS:localhost,IP:127.0.0.1
extendedKeyUsage = serverAuth
EOF


echo "Creating the Docker Server Certificate"
sudo openssl x509 -req \
                  -days 365 \
                  -in "${DOCKER_HOST_SSL_HOME}/server.csr" \
                  -CA "${DOCKER_HOST_SSL_HOME}/ca.pem" \
                  -CAkey "${DOCKER_HOST_SSL_HOME}/ca-key.pem" \
                  -CAcreateserial \
                  -out "${DOCKER_HOST_SSL_HOME}/server-cert.pem" \
                  -extfile "${DOCKER_HOST_SSL_HOME}/server-extfile.cnf"



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

echo "Removing CSR files"
sudo rm "$DOCKER_CLIENT_SSL_HOME/client.csr" "$DOCKER_HOST_SSL_HOME/server.csr"

echo "Removing OpenSSL Extention Files"
sudo rm "$DOCKER_CLIENT_SSL_HOME/extfile.cnf" "$DOCKER_HOST_SSL_HOME/server-extfile.cnf"

# configure Docker daemon
cat <<EOF > /etc/docker/daemon.json
{
  "tlsverify": true,
  "tlscacert": "$DOCKER_HOST_SSL_HOME/ca.pem",
  "tlscert": "$DOCKER_HOST_SSL_HOME/server-cert.pem",
  "tlskey": "$DOCKER_HOST_SSL_HOME/server-key.pem",
  "hosts": ["tcp://0.0.0.0:2376", "unix:///var/run/docker.sock"]
}
EOF


echo "Making Certificate World Readable"
sudo chmod -v 0444 "$DOCKER_HOST_SSL_HOME/ca.pem" "$DOCKER_HOST_SSL_HOME/server-cert.pem" "$DOCKER_HOST_SSL_HOME/client-cert.pem"

# reload systemctl and Docker service
sudo systemctl daemon-reload
sudo systemctl restart docker

set +eu
echo "Attempting to access the remote docker api without tls"
docker -H=127.0.0.1:2376 info
set -eu

echo "Now attempting to access with tls!"
docker --tlsverify \
            --tlscacert="$DOCKER_HOST_SSL_HOME/ca.pem" \
            --tlscert="$DOCKER_CLIENT_SSL_HOME/client-cert.pem" \
            --tlskey="$DOCKER_CLIENT_SSL_HOME/client-key.pem" \
            -H=127.0.0.1:2376 \
            version

ls "$DOCKER_CLIENT_SSL_HOME"
cd "$DOCKER_CLIENT_SSL_HOME"
pwd
