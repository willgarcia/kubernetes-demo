#!/usr/bin/env bash

set -eu

if [ -z "$K8S_MASTER" ]; then
  echo "Error: K8S_MASTER environment variable is missing";
  exit 1;
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[ ! -f "$WORKSPACE/k8s-env" ] && { echo "k8s.env not found..."; exit 1; }
. $WORKSPACE/k8s-env

docker run\
        --name=${CONTAINER_NAME_PREFIX}etcd-1\
        --detach\
        --net=host\
        -- gcr.io/google_containers/etcd-amd64:${ETCD_VERSION} /usr/local/bin/etcd\
             --listen-client-urls=http://127.0.0.1:4001,http://${K8S_MASTER}:4001\
             --advertise-client-urls=http://${K8S_MASTER}:4001\
             --data-dir=/var/etcd/data

ETCD_STATUS=-1
while [  $ETCD_STATUS != 0 ]; do
    ETCD_STATUS=$(docker run --net=host -- gcr.io/google_containers/etcd-amd64:2.2.1 etcdctl cluster-health >/dev/null; echo $?)
    echo "Waiting for etcd startup..."
    sleep 2
done

docker run\
        --name=${CONTAINER_NAME_PREFIX}etcd-2\
        --net=host\
        -- gcr.io/google_containers/etcd-amd64:${ETCD_VERSION}\
            etcdctl set /coreos.com/network/config '{ "Network": "10.1.0.0/16" }'

FLANNEL_CONTAINER_ID=$(
    docker run\
    --detach\
    --net=host\
    --privileged\
    -v /dev/net:/dev/net\
    -- quay.io/coreos/flannel:${FLANNEL_VERSION} /opt/bin/flanneld\
            --ip-masq=${FLANNEL_IPMASQ}\
            --iface=${FLANNEL_IFACE}
)

FLANNEL_STATUS=-1
set +e
while [  $FLANNEL_STATUS != 0 ]; do
    docker exec -- ${FLANNEL_CONTAINER_ID} cat /run/flannel/subnet.env 2>/dev/null
    FLANNEL_STATUS=$?
    echo -- "Waiting for flannel startup..."
    sleep 2
done
set -e

docker exec --\
         ${FLANNEL_CONTAINER_ID} cat /run/flannel/subnet.env | grep 'FLANNEL_SUBNET\|FLANNEL_MTU' > /etc/default/docker
echo -- "DOCKER_OPTS=\"--bip=\${FLANNEL_SUBNET} --mtu=\${FLANNEL_MTU}\"" >> "/etc/default/docker"

docker run\
    --volume=/:/rootfs:ro\
    --volume=/sys:/sys:ro\
    --volume=/var/lib/docker/:/var/lib/docker:rw\
    --volume=/var/lib/kubelet/:/var/lib/kubelet:rw\
    --volume=/var/run:/var/run:rw\
    --net=host\
    --privileged=true\
    --pid=host\
    --detach\
    -- gcr.io/google_containers/hyperkube-amd64:v${K8S_VERSION}     /hyperkube kubelet\
         --allow-privileged=true\
         --api-servers=http://localhost:8080\
         --v=2\
         --address=0.0.0.0\
         --enable-server\
         --hostname-override=127.0.0.1\
         --config=/etc/kubernetes/manifests-multi\
         --containerized

docker -- ps

exit 0
