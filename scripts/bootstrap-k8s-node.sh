#!/usr/bin/env bash

set -eu

if [ -z "$K8S_MASTER" ]; then
  echo "Error: K8S_MASTER environment variable is missing";
  exit 1;
fi


WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[ ! -f "$WORKSPACE/k8s-env" ] && { echo "k8s.env not found..."; exit 1; }
. $WORKSPACE/k8s-env

readonly CONTAINER_NAME_PREFIX="kubernetes-"

docker daemon --\
    -p /var/run/docker-bootstrap.pid\
    --iptables=false\
    --ip-masq=false\
    --bridge=none\
    --graph=/var/lib/docker-bootstrap 2> /tmp/docker-bootstrap.log 1> /dev/null &

FLANNEL_CONTAINER_ID=$(
    docker run\
            --name=${CONTAINER_NAME_PREFIX}flannel\
            --detach\
            --net=host\
            --privileged\
            -v /dev/net:/dev/net\
            -- quay.io/coreos/flannel:${FLANNEL_VERSION} /opt/bin/flanneld\
                --ip-masq=${FLANNEL_IPMASQ}\
                --etcd-endpoints=http://${K8S_MASTER}:4001\
                --iface=${FLANNEL_IFACE}
)

FLANNEL_STATUS=-1
set +e
while [  $FLANNEL_STATUS != 0 ]; do
    docker exec  -- ${FLANNEL_CONTAINER_ID} cat /run/flannel/subnet.env
    FLANNEL_STATUS=$?
    echo "Waiting for flannel startup..."
    sleep 2
done
set -e

docker exec --\
        ${FLANNEL_CONTAINER_ID} cat /run/flannel/subnet.env | grep 'FLANNEL_SUBNET\|FLANNEL_MTU' > /etc/default/docker
echo "DOCKER_OPTS=\"--bip=\${FLANNEL_SUBNET} --mtu=\${FLANNEL_MTU}\"" >> "/etc/default/docker"

docker run\
     --name=${CONTAINER_NAME_PREFIX}kubelet\
     --volume=/:/rootfs:ro\
     --volume=/sys:/sys:ro\
     --volume=/dev:/dev\
     --volume=/var/lib/docker/:/var/lib/docker:rw\
     --volume=/var/lib/kubelet/:/var/lib/kubelet:rw\
     --volume=/var/run:/var/run:rw\     --net=host\
     --privileged=true\
     --pid=host\
     --detach\
     -- gcr.io/google_containers/hyperkube-amd64:v${K8S_VERSION}\
         /hyperkube kubelet\
         --allow-privileged=true\
         --api-servers=http://${K8S_MASTER}:8080\
         --v=2\
         --address=0.0.0.0\
         --enable-server\
         --containerized

docker run\
    --name=${CONTAINER_NAME_PREFIX}proxy\
    --detach\
    --net=host\
    --privileged\
    -- gcr.io/google_containers/hyperkube-amd64:v${K8S_VERSION}     /hyperkube proxy\
        --master=http://${K8S_MASTER}:8080\
        --v=2

docker -- ps

exit 0
