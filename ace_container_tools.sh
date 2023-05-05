# Laurent Martin 2023
# execute a command inside the container (running or not)
# This script is loaded in the shell with command "source"
acedo(){
    if test -z "$(podman ps --filter name=$ace_container_name -q)";then
        podman run --interactive --tty --rm=true --name mqsicmd --env LICENSE=accept \
        --volume $ace_host_work_directory:$ace_container_work_directory --entrypoint=bash $ace_image -l -c "$*"
    else
        podman exec --interactive --tty $ace_container_name bash -l -c "$*"
    fi
}
# create command aliases on host, forwarded to container
for c in createworkdir vault credentials setdbparms;do alias mqsi$c="acedo mqsi$c";done
alias keytool='acedo keytool'
# modification of IntegrationServer config file
aceserverconf(){
  local section=$1
  local parameter=$2
  local value="$3"
  sed --in-place=.bak --regexp-extended --expression="/^\s*${section}:/,/^$/ s|#?(${parameter}:) '[^']*'|\1 '${value}'|" $ace_host_work_directory/server.conf.yaml
}
create_container_ace(){
    podman create \
        --name $ace_container_name \
        --env LICENSE=accept \
        --publish 7600:7600 \
        --publish 7700:7700 \
        --publish 7800:7800 \
        --publish 7843:7843 \
        --volume $ace_host_work_directory:$ace_container_work_directory \
        --entrypoint=bash \
        $ace_image \
        -l -c \
        "IntegrationServer --work-dir $ace_container_work_directory --vault-key $vault_key"
    echo "Container name: $ace_container_name"
    echo "Persistency volume: $ace_host_work_directory"
    echo "Manage container:"
    echo "podman start $ace_container_name"
    echo "podman stop $ace_container_name"
    echo "podman rm $ace_container_name"
    echo "podman logs -f $ace_container_name"
}
