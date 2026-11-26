#!/usr/bin/env bash
# Sinh cloud-init snippet cho worker: k8s-node.yaml (cài containerd/kubeadm) + lệnh kubeadm join.
# Kết quả: /var/lib/vz/snippets/k8s-worker.yaml (root, 600, KHÔNG commit vì chứa token).
# Chạy lại bất cứ lúc nào để đổi token (token cũ vẫn còn tới khi bạn xoá secret bootstrap-token-<id>).
set -euo pipefail
cd "$(dirname "$0")/.."

# Bootstrap token = Secret trong kube-system; kubeadm join dùng nó để xác thực lần đầu.
id=$(openssl rand -hex 3)      # 6 ký tự [a-f0-9]
secret=$(openssl rand -hex 8)  # 16 ký tự
kubectl -n kube-system create secret generic "bootstrap-token-$id" \
  --type bootstrap.kubernetes.io/token \
  --from-literal=token-id="$id" --from-literal=token-secret="$secret" \
  --from-literal=usage-bootstrap-authentication=true --from-literal=usage-bootstrap-signing=true \
  --from-literal=auth-extra-groups=system:bootstrappers:kubeadm:default-node-token \
  --from-literal=description="auto-join cho worker do OpenTofu tao (khong het han)" >/dev/null
kubectl -n kube-system label secret "bootstrap-token-$id" homelab/purpose=worker-autojoin >/dev/null

# Hash public key của CA: worker dùng để xác minh nó đang nói chuyện với ĐÚNG control-plane.
ca_hash=$(kubectl config view --raw --minify -o jsonpath="{.clusters[0].cluster.certificate-authority-data}" \
  | base64 -d | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | sha256sum | cut -d" " -f1)

{ cat nixos/k8s-node.yaml
  echo "  # --- thêm bởi tofu/gen-worker-snippet.sh: tự join cluster ---"
  echo "  - kubeadm join 10.10.10.11:6443 --token $id.$secret --discovery-token-ca-cert-hash sha256:$ca_hash"
} | sudo install -o root -g root -m 600 /dev/stdin /var/lib/vz/snippets/k8s-worker.yaml

echo "OK: /var/lib/vz/snippets/k8s-worker.yaml (token id: $id, CA hash: sha256:${ca_hash:0:12}...)"
