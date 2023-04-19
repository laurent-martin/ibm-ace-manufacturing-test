# execute a command inside the container (running or not)
acedo(){
    if test -z "$(podman ps --filter name=$ace_container_name -q)";then
        podman run --interactive --tty --rm=true --name mqsicmd --env LICENSE=accept \
        --volume $host_work_directory:$container_work_directory --entrypoint=bash $ace_image -l -c "$*"
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
  sed --in-place=.bak --regexp-extended --expression="/^\s*${section}:/,/^$/ s|#?(${parameter}:) '[^']*'|\1 '${value}'|" $host_work_directory/server.conf.yaml
}
