#!/bin/bash

# exit on error
set -e

# Generates a self-signed certificate and key in PKCS12 format
OUTDIR=$1
SSLCONFTMPL=$2

if test -z "$OUTDIR"; then
    echo "Usage: $0 <output directory>"
    exit 1
fi

if test ! -e ./private/configuration.env; then
    echo "Missing configuration file: ./private/configuration.env"
    exit 1
fi

source ./private/configuration.env

PRIVKEYFILE=${OUTDIR}/${cert_name}.key
SSLCONF=${OUTDIR}/${cert_name}.conf
CSRFILE=${OUTDIR}/${cert_name}.csr
CERTFILEPEM=${OUTDIR}/${cert_pem}
CERTFILEP12=${OUTDIR}/${cert_p12}

echo "Generating private key"
openssl genrsa -out ${PRIVKEYFILE} 4096

echo "Generating SSL config"
param_fqdn=${cert_address} envsubst < ${SSLCONFTMPL} > ${SSLCONF}

echo "Generating CSR"
openssl req -new -sha256 -out ${CSRFILE} -key ${PRIVKEYFILE} -config ${SSLCONF}

echo "Generating certificate (PEM)"
openssl x509 -req -sha256 -days 365 -in ${CSRFILE} -signkey ${PRIVKEYFILE} -out ${CERTFILEPEM} -extensions req_ext -extfile ${SSLCONF}

echo "Generating PKCS12 container"
openssl pkcs12 -password pass:"${cert_pkcs12_password}" -export -in ${CERTFILEPEM} -inkey ${PRIVKEYFILE} -out ${CERTFILEP12}
