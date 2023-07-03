#!/usr/bin/env bash
# https://hub.docker.com/_/eclipse-mosquitto
# https://mosquitto.org/

# exit on any error (set -e)
trap 'echo "ERROR: command failed";exit' ERR
script_folder="$(dirname $0)"
# load config
source $script_folder/configuration.env

case "$1" in
    start)
        mkdir -p $mosquitto_host_config
        cp $script_folder/mosquitto.conf $mosquitto_host_config
        ${container_engine} create \
        --name ${mosquitto_container_name} \
        --hostname ${mosquitto_container_name} \
        --publish ${mosquitto_port}:${mosquitto_port} \
        --volume ${mosquitto_host_config}:${mosquitto_container_config} \
        ${mosquitto_image}
        echo "Persistency volume: $host_pki_folder"
        echo "Container name: ${mosquitto_container_name}"
        echo "Manage container:"
        echo "$container_engine start ${mosquitto_container_name}"
        echo "$container_engine stop ${mosquitto_container_name}"
        echo "$container_engine rm ${mosquitto_container_name}"
        echo "$container_engine logs -f ${mosquitto_container_name}"
esac
