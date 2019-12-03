#!/bin/bash
set -ex

export AWS_SDK_LOAD_CONFIG=1

BASE=$(dirname $0)

read AWS_KMS_KEY_ARN

read CLUSTER_NAME

read -s GITHUB_TOKEN

read GITHUB_ORGANIZATION

# Create Initial Infrastructure
pushd terraform
{
    sed -i '' 's|$(CLUSTER_NAME)|'"$CLUSTER_NAME"'|g' ./main.auto.tfvars
    sed -i '' 's|$(GITHUB_TOKEN)|'"$GITHUB_TOKEN"'|g' ./main.auto.tfvars
    sed -i '' 's|$(GITHUB_ORGANIZATION)|'"$GITHUB_ORGANIZATION"'|g' ./main.auto.tfvars

    terraform init
    terraform apply -auto-approve
    terraform output -json > ./output.json

    sed -i '' 's|$(AWS_KMS_KEY_ARN)|'"$AWS_KMS_KEY_ARN"'|g' ./.sops.yaml
    sops --encrypt --in-place ./main.auto.tfvars
}
popd

# Export Terraform Output as Environment Variables
$(python ./utils/terraform_make_env.py < ./terraform/output.json)

# Commit Initial Infrastructure
pushd /tmp
{
    git clone $INFRA_REPO infra
    pushd infra
    {
        cp -R $BASE/terraform/* $BASE/terraform/.* .
        git add -A
        git commit -sm 'feat(Terraform): Initial Setup'
        git push
    }
    popd
    rm -R infra
}
popd

# Commit ArgoCD Initial Setup
pushd /tmp
{
    git clone $STATE_REPO argocd
    pushd argocd
    {
        cp -R $BASE/argocd/* .
        sed -i '' 's|$(GIT_REPOSITORY)|'"$STATE_REPO"'|g' ./argocd.yaml
        git add -A
        git commit -sm 'feat(ArgoCD): Initial Setup'
        git push
    }
    popd
    rm -R state
}
popd

# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait deployments -n argocd --all --for condition=Available
kubectl port-forward svc/argocd-server -n argocd 8080:443 & PORTFORWARD_PID=$!
ADMIN_PASSWORD=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)

# Setup ArgoCD
argocd login https://localhost:8080 --insecure --username admin --password $ADMIN_PASSWORD
argocd repo add $STATE_REPO --ssh-private-key-path ~/id_rsa
kubectl apply -k ./argocd
