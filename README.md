# Cluster management with Kubernetes

This is a *minimal* setup of [Kubernetes](kubernetes.io) with minikube on one host.

If you are interested in running all the components manually (Kubernetes, [etcd](https://github.com/coreos/etcd
) and [flannel](https://github.com/coreos/flannel))  on multiple nodes, please refer to this [guide](README-dev.md).
 .
In addition to the official documentation, if you are interested in running Kubernetes on Amazon or Google Cloud, [Kubernetes The Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way) is a good read.

With this tutorial, you will learn about:

* Multi-host deployment
* Rolling updates and rollback
* Self-healing
* Secrets and configuration for containers

## Pre-requisites

* Docker `>= 1.12.3`
* [minikube](http://kubernetes.io/docs/getting-started-guides/minikube/)
* [kubectl](http://kubernetes.io/docs/getting-started-guides/minikube/) - section install kubectl

## Create the host

Run these commands to prepare the cluster:

```
$ minikube start
....
Starting local Kubernetes cluster...
Kubectl is now configured to use the cluster.
....
$ eval $(minikube docker-env)
```

You can also use `minikube delete` to delete the cluster at any time.

## Cluster informations

Check the main  components of the cluster with `kubectl`:

```
$ kubectl cluster-info
....
Kubernetes master is running at http://localhost:8080
```


Expected output:

```
Kubernetes master is running at https://192.168.99.104:8443
KubeDNS is running at https://192.168.99.104:8443/api/v1/proxy/namespaces/kube-system/services/kube-dns
kubernetes-dashboard is running at https://192.168.99.104:8443/api/v1/proxy/namespaces/kube-system/services/kubernetes-dashboard

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

```
$ kubectl api-versions
....
apps/v1alpha1
authentication.k8s.io/v1beta1
authorization.k8s.io/v1beta1
autoscaling/v1
batch/v1
batch/v2alpha1
certificates.k8s.io/v1alpha1
extensions/v1beta1
policy/v1alpha1
rbac.authorization.k8s.io/v1alpha1
storage.k8s.io/v1beta1
v1
```

```
$ kubectl version
....
Client Version: version.Info{Major:"1", Minor:"4", GitVersion:"v1.4.6+e569a27", GitCommit:"e569a27d02001e343cb68086bc06d47804f62af6", GitTreeState:"not a git tree", BuildDate:"2016-11-12T09:26:56Z", GoVersion:"go1.7.3", Compiler:"gc", Platform:"darwin/amd64"}
Server Version: version.Info{Major:"1", Minor:"4", GitVersion:"v1.4.5", GitCommit:"5a0a696437ad35c133c0c8493f7e9d22b0f9b81b", GitTreeState:"clean", BuildDate:"1970-01-01T00:00:00Z", GoVersion:"go1.7.1", Compiler:"gc", Platform:"linux/amd64"}
```

For more details about the events happening during the startup process, run:

```
$ kubectl get events
....
LASTSEEN   FIRSTSEEN   COUNT     NAME       KIND      SUBOBJECT   TYPE      REASON                    SOURCE                  MESSAGE
3m         3m          1         minikube   Node                  Normal    Starting                  {kube-proxy minikube}   Starting kube-proxy.
3m         3m          1         minikube   Node                  Normal    Starting                  {kubelet minikube}      Starting kubelet.
3m         3m          4         minikube   Node                  Normal    NodeHasSufficientDisk     {kubelet minikube}      Node minikube status is now: NodeHasSufficientDisk
3m         3m          4         minikube   Node                  Normal    NodeHasSufficientMemory   {kubelet minikube}      Node minikube status is now: NodeHasSufficientMemory
3m         3m          4         minikube   Node                  Normal    NodeHasNoDiskPressure     {kubelet minikube}      Node minikube status is now: NodeHasNoDiskPressure
3m         3m          1         minikube   Node                  Normal    RegisteredNode            {controllermanager }    Node minikube event: Registered Node minikube in NodeController
```

Get a list of all the hosts referenced by the cluster (only one node in this case):

```
$ kubectl get nodes
NAME       STATUS    AGE
minikube   Ready     4m
```

## Kubernetes cluster status

For the following tests, open a new terminal and always keep it active with the following command running.
It will help to monitor events on all of the components of the cluster.

```
$ watch kubectl get rc,svc,pods --all-namespaces=true -o wide
```

To keep an eye on the cluster, you can also run the dashboard with this command:

```
$ minikube dashboard
```

And visit this page: `http://$(minikube ip):30000/`

## 1/5- Create a pod, multi containers

In this first example, we will attempt to create 2 pods through a replication controller.

Definitions:
* pod: a pod is a set of containers that generally works well together. All the containers inside a pod share the same virtual network where they communicate on `localhost:[port]`
* replication controller: they are responsible for maintaining a desired number of pod “replicas”. It is possible to create a pod without an associated replication controller: in a fully orchestrated environment, this is a limit because pods die and are not recreated automatically.

In our case, the replication controller defines 2 replicas (`./kube-templates/pods-multihost/busmeme-rc.yml`) to ensure that 2 instances of application will always be running across our nodes:

```
kind: ReplicationController
metadata:
  name: busmeme-rc
...
spec:
  replicas: 2 # tells deployment to run 2 pods matching the template
...
```

The pod itself will run 2 containers:

```
kind: ReplicationController
metadata:
  name: busmeme-rc
...
spec:
  containers:
  - image: mongo
    name: mongo
    ports:
...
    volumeMounts:
...
  - image: minillinim/busmemegenerator
    name: web
```

To add this new resource to the cluster, run the following command:

```
$ kubectl create -f ./kube-templates/pods-multihost/busmeme-rc.yml
```

In our active terminal running watch, the expected result is:

```
NAMESPACE     NAME                          READY     STATUS    RESTARTS   AGE       IP               NODE
default       busmeme-rc-cy6wd              0/2       Pending   0          10m       <none>
default       busmeme-rc-jjfi3              2/2       Running   0          10m       172.17.0.4       minikube
NAMESPACE     NAME                   DESIRED   CURRENT   READY     AGE       CONTAINER(S)              IMAGE(S) SELECTOR
default       busmeme-rc             2         2         1         11m       mongo,web                 mongo,minillinim/busmemegener
ator                                                                                                           name=web
```

Kubernetes attempted to create 2 pods replicas. Because `minikube` supports only one node, the second replicas can not be created and remains in a pending state, waiting for nodes to be available before deployment.

The `describe` command provides more details on a pod:
* containers running in the pod (exposed ports for 80/TCP)
* internal IPs affected to the containers within the pod
* base images used

```
$ kubectl describe pod [pod]
```

Pod are not exposed by default to the outside world. To publish your external services (typically a frontend), Kubernetes implements the concept of service. There are different types of services (`LoadBalancer`, `NodePort` or `ClusterIP`).

ClusterIP is the default type and provides a cluster-internal IP only (services are visible inside of the cluster). With the following command, we will change the type to `NodePort` to open our service `web` outside of the cluster:

```
$ kubectl create -f ./kube-templates/pods-multihost/busmeme-service.yml
```

The application should be accessible now on `http://$(minikube ip):30061/`.

Debugging
---------

Show the logs of each container running in the pod:

```
$ kubectl logs  busmeme-rc-jjfi3 mongo
....
2016-12-04T03:02:59.534+0000 I CONTROL  [initandlisten] MongoDB starting : pid=1 port=27017 dbpath=/data/db 64-bit host=busmeme-rc-jjfi3
2016-12-04T03:02:59.534+0000 I CONTROL  [initandlisten] db version v3.4.0
2016-12-04T03:02:59.534+0000 I CONTROL  [initandlisten] git version: f4240c60f005be757399042dc12f6addbc3170c1
2016-12-04T03:02:59.534+0000 I CONTROL  [initandlisten] OpenSSL version: OpenSSL 1.0.1t  3 May 2016
2016-12-04T03:02:59.534+0000 I CONTROL  [initandlisten] allocator: tcmalloc
2016-12-04T03:02:59.534+0000 I CONTROL  [initandlisten] modules: none
2016-12-04T03:02:59.534+0000 I CONTROL  [initandlisten] build environment:
2016-12-04T03:02:59.534+0000 I CONTROL  [initandlisten]     distmod: debian81
2016-12-04T03:02:59.534+0000 I CONTROL  [initandlisten]     distarch: x86_64
....
```

```
$ kubectl logs busmeme-rc-jjfi3 web
....
npm info it worked if it ends with ok
npm info using npm@2.15.5
npm info using node@v4.4.5
npm info prestart app@0.0.1
npm info start app@0.0.1

> app@0.0.1 start /app
> node app.js

Express server listening on port 3000
....
```

Attach the standard out (stdout) of a container:

```
$ kubectl attach -i [pod]
```

Execute a command inside a pod (If the container name is omitted, the first container in the pod will be chosen):

```
$ kubectl exec [pod] date
$ kubectl exec [pod] ls
$ kubectl exec [pod] echo $PATH
```

To update a pod (change the Docker base image for example), you could also use the `apply` command:

```
$ kubectl apply -f ./kube-templates/pods-multihost/busmeme-rc.yml
```

## 2/5- Desired state

Check endpoints:

```
$ kubectl describe svc busmeme-service
....
Name:			busmeme-service
Namespace:		default
Labels:			name=web
Selector:		name=web
Type:			NodePort
IP:			10.0.0.48
Port:			<unset>	4000/TCP
NodePort:		<unset>	30061/TCP
Endpoints:		10.1.14.2:3000,10.1.55.2:3000
Session Affinity:	None
No events.
```

As mentioned before, the presence of the attributes `replicas: 2` in the template `./kube-templates/pods-multihost/busmeme-rc.yml` defines that the cluster should always run 2 identical pods.

Run the following command to delete one of the pod:

```
$ kubectl delete pod busmeme-rc-jjfi3
...
default       busmeme-rc-cc6ul                    0/2       Pending       0          5s        <none>
default       busmeme-rc-cy6wd                    0/2       Pending       0          44m       <none>
default       busmeme-rc-jjfi3                    2/2       Terminating   0          44m       172.17.0.4       minikube
```

While this pod `busmeme-rc-jjfi3` is terminating, an other one (`busmeme-rc-cc6ul`) is immediately recreated: Kubernetes tries to maintain here the desirated state of the cluster.

## 3/5- Rolling updates and rollbacks

* Create a new service for the application `LBAPP`

```
$ kubectl create -f ./kube-templates/rolling-update/lbapp-svc.yml
```

* Deploy version 1 of the application:

```
$ kubectl create -f ./kube-templates/rolling-update/lbapp-v1-deployment.yml
....
deployment "lbapp-deployment" created
$ kubectl rollout history deployment/lbapp-deployment
....
deployments "lbapp-deployment"
REVISION	CHANGE-CAUSE
1		<none>
2		<none>
```

The application LBAPP (accessible on http://$(minikup ip):30062) should display the current version of the application (*version 1*).

* Deploy version 2 of the application

```
$ kubectl replace -f ./kube-templates/rolling-update/lbapp-v2-deployment.yml
....
deployment "lbapp-deployment" replaced
$ kubectl rollout history deployment/lbapp-deployment
....
kubectl rollout history deployment/lbapp-deployment
deployments "lbapp-deployment"
REVISION	CHANGE-CAUSE
1		<none>
2		<none>
```

Kubernetes will start to terminate current containers and replace them by the new version as required via the previous command.

The application LBAPP (accessible on http://$(minikup ip):30062) should display the current version of the application (*version 2*).

* Rollback

```
$ kubectl rollout undo deployment/lbapp-deployment --to-revision=1
....
deployment "lbapp-deployment" rolled back
```

The application LBAPP has been rollbacked to first version. Now the application should display *version 1* as the current version.

## 4/5- Secrets

```
$ kubectl create secret generic lbapp-db --from-literal='lbapp-dbuser=produser' --from-literal='lbapp-dbpwd=twkubernetes'
....
secret "lbapp-db" created
$ kubectl get secrets
....
NAME                  TYPE                                  DATA      AGE
default-token-gqwaw   kubernetes.io/service-account-token   3         55m
lbapp-db              Opaque                                2         15s
```

To demonstrate that the secrets have been transmitted to the pod, update the pod:

```
$ kubectl apply -f ./kube-templates/secrets/lbapp-v3-secret.yml
....
deployment "lbapp-deployment" configured
```

The application LBAPP (accessible on http://$(minikup ip):30062) should display the secrets in plain text.

## 5/5- Self-healing

We have modified the template `./kube-templates/self-healing/lb-app-probe.yml` to add a healtch check based on the presence of a file inside the container `/tmp/lbapp.lock`:

```
livenessProbe:
     exec:
       command:
         - cat
         - /tmp/lbapp.lock
     initialDelaySeconds: 15
     timeoutSeconds: 1
   name: liveness
```

Apply this check by running:

```
$ kubectl replace -f ./kube-templates/self-healing/lb-app-probe.yml
```

Because the file `/tmp/lbapp.lock` is intentionally missing, the pod is flagged as unhealthy and after a certain amount of retries and its status goes from `Running` to `CrashLoopBackOff`

```
 FirstSeen	LastSeen	Count	From				SubobjectPath			Type		Reason			Message
  ---------	--------	-----	----				-------------			--------	------			-------
  3m		3m		1	{default-scheduler }						Normal		Scheduled		Successfully assigned lbapp-rc-m2eoe to second-host
  3m		3m		1	{kubelet second-host}	spec.containers{liveness}	Normal		Started			Started container with docker id 7dc6893a5f79
  3m		3m		1	{kubelet second-host}	spec.containers{liveness}	Normal		Created			Created container with docker id 7dc6893a5f79
  2m		2m		1	{kubelet second-host}	spec.containers{liveness}	Normal		Killing			Killing container with docker id 7dc6893a5f79: pod "lbapp-rc-m2eoe_default(755cd7f6-3387-11e6-ac39-080027048954)" container "liveness" is unhealthy, it will be killed and re-created.
  2m		2m		1	{kubelet second-host}	spec.containers{liveness}	Normal		Created			Created container with docker id eade5a04a45f
  2m		2m		1	{kubelet second-host}	spec.containers{liveness}	Normal		Started			Started container with docker id eade5a04a45f
  1m		1m		1	{kubelet second-host}	spec.containers{liveness}	Normal		Killing			Killing container with docker id eade5a04a45f: pod "lbapp-rc-m2eoe_default(755cd7f6-3387-11e6-ac39-080027048954)" container "liveness" is unhealthy, it will be killed and re-created.
  1m		1m		1	{kubelet second-host}	spec.containers{liveness}	Normal		Started			Started container with docker id 95e53548eef4
  1m		1m		1	{kubelet second-host}	spec.containers{liveness}	Normal		Created			Created container with docker id 95e53548eef4
  1m		1m		1	{kubelet second-host}	spec.containers{liveness}	Normal		Killing			Killing container with docker id 95e53548eef4: pod "lbapp-rc-m2eoe_default(755cd7f6-3387-11e6-ac39-080027048954)" container "liveness" is unhealthy, it will be killed and re-created.
  1m		1m		1	{kubelet second-host}	spec.containers{liveness}	Normal		Started			Started container with docker id 00524bc95109
  1m		1m		1	{kubelet second-host}	spec.containers{liveness}	Normal		Created			Created container with docker id 00524bc95109
  3m		36s		5	{kubelet second-host}	spec.containers{liveness}	Normal		Pulling			pulling image "willgarcia/lb-app"
  36s		36s		1	{kubelet second-host}	spec.containers{liveness}	Normal		Killing			Killing container with docker id 00524bc95109: pod "lbapp-rc-m2eoe_default(755cd7f6-3387-11e6-ac39-080027048954)" container "liveness" is unhealthy, it will be killed and re-created.
  30s		30s		1	{kubelet second-host}	spec.containers{liveness}	Normal		Started			Started container with docker id 2e61ea30e7f4
  3m		30s		5	{kubelet second-host}	spec.containers{liveness}	Normal		Pulled			Successfully pulled image "willgarcia/lb-app"
  3m		30s		6	{kubelet second-host}					Warning		MissingClusterDNS	kubelet does not have ClusterDNS IP configured and cannot create Pod using "ClusterFirst" policy. Falling back to DNSDefault policy.
  30s		30s		1	{kubelet second-host}	spec.containers{liveness}	Normal		Created			Created container with docker id 2e61ea30e7f4
  3m		26s		7	{kubelet second-host}	spec.containers{liveness}	Warning		Unhealthy		Liveness probe failed: cat: /tmp/lbapp.lock: No such file or directory
```

Combined with restart policies and monitoring, this approach is useful in production to automatically restart services or conversely stop a broken service.

# Resources

## Add-ons

https://github.com/kubernetes/kubernetes/tree/master/cluster/addons
https://github.com/kubernetes/kubedash


## Tutorial/Help docs

* https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG.md#action-required
* http://kubernetes.io/docs/user-guide/accessing-the-cluster/#accessing-the-cluster-api
* http://kubernetes.io/docs/user-guide/kubectl/kubectl_exec/
* http://kubernetes.io/docs/user-guide/configuring-containers/#configuration-in-kubernetes
* http://kubernetes.io/docs/user-guide/walkthrough/#kubectl-cli
* http://kubernetes.io/docs/user-guide/ui/
* http://kubernetes.io/docs/admin/node/#what-is-a-node
* http://kubernetes.io/docs/user-guide/pods/multi-container/
* http://kubernetes.io/docs/user-guide/deployments/#what-is-a-deployment
* http://kubernetes.io/docs/user-guide/debugging-pods-and-replication-controllers/
* https://github.com/kubernetes/kubernetes/wiki/Debugging-FAQ
* http://kubernetes.io/docs/user-guide/walkthrough/k8s201/
* http://kubernetes.io/docs/user-guide/labels/#motivation
* http://kubernetes.io/docs/user-guide/replication-controller/#what-is-a-replication-controller
* http://kubernetes.io/docs/user-guide/production-pods/#resource-management
* http://kubernetes.io/docs/user-guide/production-pods/#liveness-and-readiness-probes-aka-health-checks
* https://github.com/kubernetes/kubernetes/blob/release-1.3/docs/design/secrets.md

## Examples

* https://github.com/kubernetes/kubernetes/tree/master/examples
* https://github.com/kubernetes/kubernetes/tree/release-1.2/examples/guestbook/
* http://kubernetes.io/docs/user-guide/update-demo/
* http://kubernetes.io/docs/user-guide/services/#type-loadbalancer
* http://kubernetes.io/docs/user-guide/deploying-applications/
