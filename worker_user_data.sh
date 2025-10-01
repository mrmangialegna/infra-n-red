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
yum install -y kubelet kubeadm
systemctl enable kubelet

# Wait for master to be ready and get join command
for i in {1..30}; do
  JOIN_CMD=$(aws ssm get-parameter --name "/paas/k8s-join-command" --with-decryption --region ${region} --query 'Parameter.Value' --output text 2>/dev/null) && break
  sleep 30
done

# Join cluster
eval $JOIN_CMD
