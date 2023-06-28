# Laurent Martin 2023
# execute a command inside the container (running or not)
# This script is loaded in the shell with command "source"
if test -z "$ace_container_name"; then
    set -a
    # script is "sourced", bash uses BASH_SOURCE, and zsh uses $0
    source $(dirname "${BASH_SOURCE[0]:-$0}")/configuration.env
    set +a
fi
acedo(){
    if test -z "$($container_engine ps --filter name=$ace_container_name -q)";then
        $container_engine run --interactive --tty --rm=true --name mqsicmd --env LICENSE=accept \
        --volume $ace_host_work_directory:$ace_container_work_directory --entrypoint=bash $ace_image -l -c "$*"
    else
        $container_engine exec --interactive --tty $ace_container_name bash -l -c "$*"
    fi
}
# modification of IntegrationServer config file
aceserverconf(){
  local section=$1
  local parameter=$2
  local value="$3"
  sed --in-place=.bak --regexp-extended --expression="/^\s*${section}:/,/^$/ s|#?(${parameter}:) '[^']*'|\1 '${value}'|" $ace_host_work_directory/server.conf.yaml
}
create_container_ace(){
    if test ! -e $ace_host_work_directory;then
        echo "Work directory does not exist: $ace_host_work_directory" 1>&2
        return 1
    fi
    $container_engine create \
        --name $ace_container_name \
        --env LICENSE=accept \
        --publish ${ace_port_admin}:${ace_port_admin} \
        --publish ${ace_port_debug}:${ace_port_debug} \
        --publish ${ace_port_http}:${ace_port_http} \
        --publish ${ace_port_https}:${ace_port_https} \
        --volume $ace_host_work_directory:$ace_container_work_directory \
        --entrypoint=bash \
        $ace_image \
        -l -c \
        "IntegrationServer --work-dir $ace_container_work_directory --vault-key $vault_key"
    echo "Container name: $ace_container_name"
    echo "Persistency volume: $ace_host_work_directory"
    echo "Manage container:"
    echo "$container_engine start $ace_container_name"
    echo "$container_engine stop $ace_container_name"
    echo "$container_engine rm $ace_container_name"
    echo "$container_engine logs -f $ace_container_name"
}
# expand aliases, even if not interactive
shopt -s expand_aliases
# create command aliases on host, forwarded to container
for c in createworkdir vault credentials setdbparms;do alias "mqsi$c=acedo mqsi$c";done
alias keytool='acedo keytool'
alias ibmint='acedo ibmint'
