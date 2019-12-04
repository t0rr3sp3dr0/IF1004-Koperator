#!/bin/bash
set -ex

shopt -s dotglob

export AWS_SDK_LOAD_CONFIG=1
export GLOBIGNORE=.:..

BASE=$(dirname $0)
BASE=$(realpath $BASE)

read AWS_KMS_KEY_ARN
read CLUSTER_NAME
read -s GITHUB_TOKEN
read GITHUB_ORGANIZATION

# Generate Deployment Key
TMPDIR=$(mktemp -d)
ssh-keygen -b 4096 -t rsa -P '' -C '' -f $TMPDIR/id_rsa

# Create Initial Infrastructure
pushd terraform
{
    sed -i '' 's|$(CLUSTER_NAME)|'"$CLUSTER_NAME"'|g' ./main.auto.tfvars
    sed -i '' 's|$(GITHUB_TOKEN)|'"$GITHUB_TOKEN"'|g' ./main.auto.tfvars
    sed -i '' 's|$(GITHUB_ORGANIZATION)|'"$GITHUB_ORGANIZATION"'|g' ./main.auto.tfvars
    sed -i '' 's|$(STATE_ARGOCD_KEY)|'"$(cat $TMPDIR/id_rsa.pub | sed 's/ *$//g')"'|g' ./main.auto.tfvars

    terraform fmt
    terraform init
    terraform apply -auto-approve
    terraform output -json > ./output.json

    sed -i '' 's|$(AWS_KMS_KEY_ARN)|'"$AWS_KMS_KEY_ARN"'|g' ./.sops.yaml
    sops --encrypt --in-place ./main.auto.tfvars

    # workaround for https://github.community/t5/_/_/m-p/28259
    # go to https://github.com/0rg4n1z4t10n/$CLUSTER_NAME-INFRA/settings/secrets
    # create AWS_ACCESS_KEY_ID secret
    # create AWS_SECRET_ACCESS_KEY secret
    # create AWS_DEFAULT_REGION secret
    read
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
        cp -R $BASE/terraform/* .
        git add -A
        git commit -sm 'feat(Terraform): Initial Setup'
        git push
    }
    popd
    rm -fR infra
}
popd

# Commit ArgoCD Initial Setup
pushd /tmp
{
    git clone $STATE_REPO argocd
    pushd argocd
    {
        sed -i '' 's|$(GIT_REPOSITORY)|'"$STATE_REPO"'|g' $BASE/argocd/argocd.yaml
        cp -R $BASE/argocd/* .
        git add -A
        git commit -sm 'feat(ArgoCD): Initial Setup'
        git push
    }
    popd
    rm -fR argocd
}
popd

# Install ArgoCD
while [ "${ARGOCD_PORT:-0}" -le 1024 ]
do
    ARGOCD_PORT=$RANDOM
done
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait deployments -n argocd --all --for condition=Available --timeout 5m
kubectl port-forward svc/argocd-server -n argocd $ARGOCD_PORT:443 & PORTFORWARD_PID=$!
ARGOCD_PASSWORD=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)
until nc -z localhost $ARGOCD_PORT
do
    sleep 1
done

# Setup ArgoCD
argocd login localhost:$ARGOCD_PORT --insecure --username admin --password $ARGOCD_PASSWORD
argocd repo add $STATE_REPO --ssh-private-key-path $TMPDIR/id_rsa
kubectl apply -k ./argocd
argocd app sync argocd

git stash -a
