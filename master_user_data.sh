#!/bin/bash
set -eux

# Update system
yum update -y

# Install containerd
yum install -y containerd
systemctl enable --now containerd

# Configure containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
systemctl restart containerd

# Add Kubernetes repo
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
EOF

# Install Kubernetes
yum install -y kubelet kubeadm kubectl
systemctl enable kubelet

# Initialize cluster
kubeadm init --pod-network-cidr=10.244.0.0/16 > /tmp/kubeadm-init.log

# Setup kubeconfig
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config

# Save join command to Parameter Store
JOIN_CMD=$(tail -n 2 /tmp/kubeadm-init.log | tr '\n' ' ')
aws ssm put-parameter --name "/paas/k8s-join-command" --value "$JOIN_CMD" --type "SecureString" --region ${region} --overwrite

# Install Flannel CNI
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Install Cluster Autoscaler
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
