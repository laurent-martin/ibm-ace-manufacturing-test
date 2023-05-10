#!/usr/bin/bash
# exit on any error (set -e)
trap 'echo "ERROR: command failed";exit' ERR
#set -x
# load variables and helper aliases to run commands in container
source ace_container_tools.rc.sh
if test -d "$ace_host_work_directory";then
    echo "Work directory already exists: $ace_host_work_directory" 1>&2
    exit 1
fi
# login to allow image pull
podman login cp.icr.io -u cp --password-stdin <<< $entitlement_key
# prepare work dir
mkdir -p $ace_host_work_directory
chmod 777 $ace_host_work_directory
mqsicreateworkdir $ace_container_work_directory
# extract ACMfg runtime and update configuration accordingly
mkdir -p $ace_host_work_directory/ACMfg_runtime
tar zxf $acmfg_tar --directory=$ace_host_work_directory/ACMfg_runtime/. --strip-components=3 ACMfg-$acmfg_version/runtime/amd64_linux_2
acmfg_runtime_folder=${ace_container_work_directory}/ACMfg_runtime envsubst < server.conf.tmpl.yaml | sudo tee $ace_host_work_directory/overrides/server.conf.yaml > /dev/null
# create the vault and PKCS12 password
mqsivault --work-dir $ace_container_work_directory --create --vault-key $vault_key
mqsicredentials \
--work-dir $ace_container_work_directory \
--vault-key $vault_key \
--create \
--credential-type ldap \
--credential-name $source_mapping_path/acmfgPrivateKeyUser \
--username not_used \
--password "$pkcs12_key"
# Some help on next commands
cat<<EOF
To create the container:
source ace_container_tools.rc.sh
create_container_ace
EOF