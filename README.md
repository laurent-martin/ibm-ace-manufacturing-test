# Testing the IBM Manufacturing pack for IBM App Connect Enterprise

IBM ACE is also available with an extension supporting the [OPC UA](https://en.wikipedia.org/wiki/OPC_Unified_Architecture) interface, as a client.

For testing purpose an OPC UA server (generating samples) is needed.

We can use the OPC PLC server.

The communication can be either un-encrypted (for tests only) or encrypted, but in that case X509 certificates must be put in place (both sides).

> **Note:** The Makefile is intended to be run on a Unix-like system (macOS, Linux)

![ACEmfg](images/ACEmfg.png)

[Nice IBM Performance Report here](https://www.ibm.com/support/pages/ibm-app-connect-manufacturing-v20-performance-reports).

## ACE: Configuration

### Without Encryption

For testing purpose **only**, it is possible to register a server without encryption and authentication.
This is much simpler than using certificates.

> **Note:** The configuration of the startup script `start_opc.sh` allows connection from client without encryption.
(option `--unsecuretransport`)

ACE Configuration:

- **Message Security Mode** : None
- **Security Policy** : None
- **Client Private Key file** : leave empty
- **Private Key password** : leave empty
- **Client Certificate file** : leave empty

### Generation of client certificate

In production, Security will be used, this requires certificates on both the client and server.

The [ACE documentation](https://www.ibm.com/docs/en/app-connect/12.0?topic=source-generating-self-signed-ssl-certificate)
provides the steps to generate a self-signed certificate.

A `Makefile` is provided here to generate a simple self-signed certificate in the required format.
It simply follows the manual steps described in the documentation.

First initialize the config, execute:

```bash
make init
```

This creates the folder `private` and file `private/config.env`

Edit this file and fill specific information:

```bash
CLIENT_ADDRESS=192.168.0.100
SERVER_ADDRESS=192.168.0.101
PASSPHRASE=_your_passphrase_here_
```

Then generate the certificate and key:

```bash
make
```

Generated files are located in folder `build`.

Copy files: `build/clientCertificate.crt` and `build/clientCertificate.p12` to the ACE workspace.

- **Message Security Mode** : `SignAndEncrypt`
- **Security Policy** : `Basic256Sha256`
- **Client Private Key file** : `[path to workspace]/clientCertificate.p12`
- **Private Key password** : the password used for the PKCS12 container
- **Client Certificate file** : `[path to workspace]/clientCertificate.key`

### Comments on documentation

A few comments on the ACE documentation:

- The ACE OPC UA client requires: The certificate's Private Key, the Key's passphrase, and the certificate.
- The documentation provides the steps to generate those. (used in the script)
- The documentation talks about "[PEM](https://en.wikipedia.org/wiki/Privacy-Enhanced_Mail)" format for both.
- The method proposed in documentation shows a PKCS12 container is generated.
- The UI tells, for the key: **Client Private Key in pem file (BASE64)**

In fact, the values to provide are:

- **Client Private Key file** : Expects the [PKCS12](https://fr.wikipedia.org/wiki/PKCS12) container, not PEM BASE64
- **Private Key password** : the password for the PKCS12 container
- **Client Certificate file** : The certificate in PEM format

If the key is not provided in the PKCS12 container, then the following error is logged:

```text
ERROR! IIC2037E: Caught exception when trying to load the client certificate and key from C:\...\clientCertificate.crt and C:\...\clientCertificate.key respectively, for data source /Source/xxx. stream does not represent a PKCS12 key store
```

The content of the PKCS12 container (with both the key and certificate) can be displayed with:

```bash
openssl pkcs12 -info -in build/clientCertificate.p12 -nodes -password pass:_pass_here_
```

## Issue: create button greyed out

In some cases, the `Create Data Source` button in the ACE manufacturing view stays greyed out.

In this case:

1. Make sure you have created a data source in the folder above the data source properties, and that it is selected.

2. If that persists, close the toolkit, and restart. Eventually, the button shall be black.

### Server certificate

The ACE OPC UA client allows (for testing) to accept the server certificate manually:

![accept cert](images/accept.png)

## OPC PLC server: Some details

In order to simulate the manufacturing side, a simulator can be used.
We use here the [OPC PLC server](https://github.com/Azure-Samples/iot-edge-opc-plc).

The current working directory in the container is : `/app`, as can be seen in the log:

```text
[INF] Current directory: /app
...
[INF] Application Certificate store path is: pki/own
...
[INF] Trusted Issuer Certificate store path is: pki/issuer
...
[INF] Trusted Peer Certificate store path is: pki/trusted
...
[INF] Rejected Certificate store path is: pki/rejected
```

So, the default folders used in the container are:

```text
/app
   /pki
      /own
      /issuer
      /trusted
      /rejected
```

If no server certificate is provided, the server generates a self signed certificate containing the hostname (of the container, so we fix the hostname value on container startup) in `/app/pki/own`.

On the podman host, in the user's home, we create a folder `pki` and copy the file `clientCertificate.crt` in it.

When the container is started, a volume is created to map this `pki` folder in the user's home to the `/app/pki` folder in the container.

The simulator is given the path to the client certificate (in the container) to add it to the trusted store.

This is automated here (copy startup script and certificate to podman host):

```bash
make deploy
```

## Server startup

The startup script is provider for convenience: `start_opc.sh`

Several parameters are provided to allow unencrypted use, trust of client cert, fix the container hostname.

### Note on server generated self signed certificate

Note that the server runs in the container, which has a hostname defaulting to the container id.
So default certificates would be generated with that changing hostname.
And this will make subsequent start fail due to the changing name.
So we fix the container host name, so that the generated server certificate can be re-used.
(in case we need it on the client side).

<!-- cspell:ignore PKCS unsecuretransport -->
