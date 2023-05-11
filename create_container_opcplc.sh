#!/usr/bin/env bash
# https://github.com/Azure-Samples/iot-edge-opc-plc#command-line-reference
# exit on any error (set -e)
trap 'echo "ERROR: command failed";exit' ERR
# load config
source configuration.env
# folder where this script is located
host_main_folder=$(realpath $(dirname "$0"))/
# (fixed value) path in the container image (WORKDIR)
container_app_folder=/app/
# (fixed value) default value for options ap, tp, rp, ip
container_pki_folder=${container_app_folder}pki
# persistency folder on host
host_pki_folder=${host_main_folder}pki
# the client's certificate to add to the server configuration (path in container)
clt_crt=$container_pki_folder/$cert_pem
# OPC port on host, default in container is 50000
opc_port=50000
# web port on host, default in container is 8080, serves http://....:8080/pn.json
web_port=8080
# create host pki folder
mkdir -p $host_pki_folder/{issuer,trusted}
# place client certificate
cp $cert_pem $host_pki_folder
$container_engine create \
--name opcplc                 `#name of container`\
--hostname opcplc             `#set a fixed hostname as the opc server takes it to generate the certificate CN`\
--publish $opc_port:50000     `#port for opcua server`\
--publish $web_port:8080      `#port to serve http://....:8080/pn.json`\
--volume $host_pki_folder:$container_pki_folder `# volume for persistency of certificates`\
`# container engine options before this line ========================================`\
mcr.microsoft.com/iotedge/opc-plc:latest `# OPC UA simulator container image`\
`# opc ua server options after this line ========================================`\
--addtrustedcertfile=$clt_crt `#add this client certificated to trusted certificates`\
--autoaccept                  `#all certs are trusted when a connection is established`\
--unsecuretransport           `#enables the unsecured transport (test only)`\
--loglevel=debug              `#fatal, error, warn, info, debug, verbose`\
--showpnjsonph                `#show OPC Publisher configuration file on log and activate the publish port`\
`# simulation options after this line ----------------------------------`\
--slownodes=500               `#number of slow nodes`\
--slowrate=5                  `#rate in seconds to change slow nodes`\
--slowtype=uint               `#data type of slow nodes (UInt-Double-Bool-UIntArray)`  \
--slowtypelowerbound=500      `#lower bound of data type of slow nodes`\
--slowtypeupperbound=1000     `#lower bound of data type of slow nodes`\
--slowtyperandomization=true  `#randomization of fast nodes value`\
--fastnodes=1000              `#number of fast nodes`\
--fastrate=1                  `#rate in seconds to change fast nodes`\
--fasttype=double             `#data type of fast nodes (UInt-Double-Bool-UIntArray)`\
--fasttypelowerbound=0        `#lower bound of data type of fast nodes`\
--fasttypeupperbound=100      `#lower bound of data type of fast nodes`\
--fasttyperandomization=true  `#randomization of fast nodes value`\
--fasttypestepsize=0.2        `#step or increment size of fast nodes value`\
--guidnodes=5                 `#number of nodes with deterministic GUID IDs`\
"$@"                          `#forward additional options from command line`

echo "Persistency volume: $host_pki_folder"
echo "Container name: opcplc"
echo "Manage container:"
echo "$container_engine start opcplc"
echo "$container_engine stop opcplc"
echo "$container_engine rm opcplc"
echo "$container_engine logs -f opcplc"

#my_address=$(hostname -I|tr \  \\n|grep -v '^10\.')
#--trustowncert                `#the own certificate is put into the trusted certificate store automatically.`\
#--certdnsnames=${my_address}  `#add additional DNS names or IP addresses to this applications certificate`\
#--appcertstorepath=/appdata \
#--dontrejectunknownrevocationstatus \
#--disablecertauth             `#disable certificate authentication`\
#--disableusernamepasswordauth `#disable username/password authentication`\
