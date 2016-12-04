# Cluster management with Kubernetes

This is a *development* setup to [Kubernetes](kubernetes.io) with [etcd](https://github.com/coreos/etcd
) and [flannel](https://github.com/coreos/flannel). Use at your own risk.

## Pre-requisites

* Kubectl client `>= 1.4.*` - see [install kubectl section](http://kubernetes.io/docs/getting-started-guides/minikube/)
* Docker `>= 1.12.3`
* 2 Linux hosts (tested with Ubuntu 14)

## Bootstrap the Kubernetes cluster

Run this command in a terminal session on your master node:

```
$ K8S_MASTER=[ip-address-master] ./scripts/boostrap-k8s-master.sh
```

~Expected output of `docker ps`:

```
CONTAINER ID        IMAGE                                             COMMAND                  CREATED             STATUS              PORTS               NAMES
d198b102d9bd        gcr.io/google_containers/hyperkube-amd64:v1.2.1   "/hyperkube kubelet -"   4 seconds ago       Up 4 seconds                            ecstatic_jennings
0b6ba024fcb5        quay.io/coreos/flannel:0.5.5                      "/opt/bin/flanneld --"   4 seconds ago       Up 4 seconds                            small_brattain
f72314c93c37        gcr.io/google_containers/etcd-amd64:2.2.1         "/usr/local/bin/etcd "   7 seconds ago       Up 7 seconds                            kubernetes-etcd-1
```

## Create a node and make it join the Kubernetes cluster

```
$ K8S_MASTER=[ip-address-master] ./scripts/boostrap-k8s-node.sh
```

~Expected output of `docker ps`:

```
CONTAINER ID        IMAGE                                             COMMAND                  CREATED             STATUS              PORTS               NAMES
803245b967d9        gcr.io/google_containers/hyperkube-amd64:v1.2.1   "/hyperkube proxy --m"   22 seconds ago      Up 21 seconds                           kubernetes-proxy
b48a9c07c733        gcr.io/google_containers/hyperkube-amd64:v1.2.1   "/hyperkube kubelet -"   22 seconds ago      Up 21 seconds                           kubernetes-kubelet
54ecc1104240        quay.io/coreos/flannel:0.5.5                      "/opt/bin/flanneld --"   22 seconds ago      Up 22 seconds                           kubernetes-flannel
```

`kubectl get nodes` should list 2 nodes now.

## Run Kubernetes dashboard:

This command starts the dashboard as a container:

```
$ docker run\
    --net=host\
    --rm\
    -it\
        gcr.io/google_containers/kubernetes-dashboard-amd64:v1.1.0-beta3\
            --apiserver-host http://[K8S_MASTER_IP]:8080
```

And visit the dashboard: `http://[K8S_MASTER_IP]:9090/`
