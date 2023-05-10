#!/usr/bin/bash
# exit on any error (set -e)
trap 'echo "ERROR: command failed";exit' ERR
# set -x
# load variables and helper aliases to run commands in container
source ace_container_tools.rc.sh
if test -d "$ace_host_work_directory";then
    echo "Work directory already exists: $ace_host_work_directory" 1>&2
    exit 1
fi
mkdir -p $ace_host_work_directory
chmod 777 $ace_host_work_directory
type mqsicreateworkdir
mqsicreateworkdir $ace_container_work_directory
mkdir -p $ace_host_work_directory/ACMfg_runtime
tar zxvf $acmfg_tar --directory=$ace_host_work_directory/ACMfg_runtime/. --strip-components=3 ACMfg-$acmfg_version/runtime/amd64_linux_2
sudo cp server.conf.yaml $ace_host_work_directory/overrides/.
mqsivault --work-dir $ace_container_work_directory --create --vault-key $vault_key
mqsicredentials \
--work-dir $ace_container_work_directory \
--vault-key $vault_key \
--create \
--credential-type ldap \
--credential-name $source_mapping_path/acmfgPrivateKeyUser \
--username not_used \
--password "$pkcs12_key"
cat<<EOF
To create the container:
source ace_container_tools.rc.sh
create_container_ace
EOF