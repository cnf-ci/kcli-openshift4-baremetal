#!/usr/bin/env bash

set -euo pipefail
set -x

dnf -y install libvirt-libs libvirt-client ipmitool mkisofs tmux make git bash-completion vim-enhanced
dnf -y install python3

update-ca-trust extract

curl -Ls https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 > /usr/bin/jq	
chmod u+x /usr/bin/jq

cd /root/bin
kcli download oc
mv oc /usr/bin
chmod +x /usr/bin/oc

curl -L https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl > /usr/bin/kubectl
chmod u+x /usr/bin/kubectl

kcli download openshift-install -P version={{ version }} -P tag={{ tag }} -P pull_secret=/root/openshift_pull.json -P baremetal=true
mv openshift-baremetal-install /usr/bin/openshift-install
chmod u+x /usr/bin/openshift-install
openshift-install version | grep 'release image' | cut -d' ' -f3 > /root/version.txt

dnf install podman skopeo -y

curl -s -L https://github.com/karmab/tasty/releases/download/v0.7.0/tasty-linux-amd64 > /usr/bin/tasty
chmod u+x /usr/bin/tasty
tasty config --enable-as-plugin

oc completion bash >>/etc/bash_completion.d/oc_completion
