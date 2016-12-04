#!/usr/bin/env bash

set -eu

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

WORKSPACE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[ ! -f "$WORKSPACE/k8s-env" ] && { echo "k8s.env not found..."; exit 1; }
. $WORKSPACE/k8s-env

if [ ! -f "./kubectl" ]; then
  wget -- http://storage.googleapis.com/kubernetes-release/release/v${K8S_VERSION}/bin/linux/amd64/kubectl
  mv -- "./kubectl" "/usr/local/bin"
  chmod -- 755 "/usr/local/bin/kubectl"
fi

exit 0
