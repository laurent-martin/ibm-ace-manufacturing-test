#!/usr/bin/bash
# https://github.com/Azure-Samples/iot-edge-opc-plc#command-line-reference

set -x
host_main_folder=$(realpath $(dirname "$0"))
container_app_folder=/app
container_pki_folder=${container_app_folder}/pki
host_pki_folder="$host_main_folder/pki"
mkdir -p $host_pki_folder
set +x
exec podman run \
--rm \
--interactive \
--tty \
--hostname opcplc             ` #hostname : set a fixed hostname as the opc server takes it to generate the cert` \
--publish 50000:50000         ` #port for opcua` \
--publish 8080:8080           ` #port to serve http://....:8080/pn.json ` \
--volume $host_pki_folder:$container_pki_folder \
--name opcplc \
mcr.microsoft.com/iotedge/opc-plc:latest ` #==container image=================================================`\
--unsecuretransport           ` #enables the unsecured transport (test only)` \
--addtrustedcertfile=${container_pki_folder}/clientCertificate.crt \
--loglevel=debug              ` #fatal, error, warn, info, debug, verbose` \
--disableusernamepasswordauth ` #disable username/password authentication` \
--portnum=50000               ` #the server port of the OPC server endpoint` \
--autoaccept                  ` #all certs are trusted when a connection is established` \
--showpnjsonph                ` #show OPC Publisher configuration file` \
--slownodes=500               ` #number of slow nodes` \
--slowrate=5                  ` #rate in seconds to change slow nodes` \
--slowtype=uint               ` #data type of slow nodes (UInt-Double-Bool-UIntArray)`  \
--slowtypelowerbound=500      ` #lower bound of data type of slow nodes` \
--slowtypeupperbound=1000     ` #lower bound of data type of slow nodes` \
--slowtyperandomization=true  ` #randomization of fast nodes value` \
--fastnodes=1000              ` #number of fast nodes` \
--fastrate=1                  ` #rate in seconds to change fast nodes` \
--fasttype=double             ` #data type of slow nodes (UInt-Double-Bool-UIntArray)` \
--fasttypelowerbound=0        ` #lower bound of data type of slow nodes` \
--fasttypeupperbound=100      ` #lower bound of data type of slow nodes` \
--fasttyperandomization=true  ` #randomization of fast nodes value` \
--fasttypestepsize=0.2        ` #step or increment size of fast nodes value ` \
--guidnodes=5                 ` #number of nodes with deterministic GUID IDs` \
"$@"

# --trustowncert                ` #the own certificate is put into the trusted certificate store automatically.` \
#--certdnsnames=${my_address}  ` #add additional DNS names or IP addresses to this applications certificate` \
#my_address=$(hostname -I|tr \  \\n|grep -v '^10\.')
# --appcertstorepath=/appdata \
# --dontrejectunknownrevocationstatus \
#--disablecertauth             ` #disable certificate authentication` \
