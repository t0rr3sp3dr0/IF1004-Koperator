#!/bin/bash
set -ex

shopt -s dotglob

export AWS_SDK_LOAD_CONFIG=1
export GLOBIGNORE=.:..

BASE=$(dirname $0)
BASE=$(realpath $BASE)

# read AWS_KMS_KEY_ARN
read CLUSTER_NAME
read CLUSTER_NAMESPACE
read GITHUB_ORGANIZATION

# Generate Deployment Key
TMPDIR=$(mktemp -d)
ssh-keygen -b 4096 -t rsa -P '' -C '' -f $TMPDIR/id_rsa

# Create and Commit Namespace Infrastructure
pushd /tmp
{
    git clone git@github.com:$GITHUB_ORGANIZATION/$CLUSTER_NAME-INFRA.git infra
    pushd infra
    {
        sops --decrypt --in-place ./main.auto.tfvars

        for PATCH in $BASE/terraform/*.patch
        do
            sed -i '' 's|$(CLUSTER_NAMESPACE)|'"$CLUSTER_NAMESPACE"'|g' $PATCH
            sed -i '' 's|$(STATE_KEY)|'"$(cat $TMPDIR/id_rsa.pub | sed 's/ *$//g')"'|g' $PATCH
            git apply $PATCH
        done

        terraform fmt
        terraform init
        terraform apply -auto-approve
        terraform output -json > $BASE/terraform/output.json

        sops --encrypt --in-place ./main.auto.tfvars

        # workaround for https://github.community/t5/_/_/m-p/28259
        # go to https://github.com/0rg4n1z4t10n/$CLUSTER_NAME-INFRA/settings/secrets
        # create AWS_ACCESS_KEY_ID secret
        # create AWS_SECRET_ACCESS_KEY secret
        # create AWS_DEFAULT_REGION secret
        read

        git add -A
        git commit -sm "feat(Terraform): $CLUSTER_NAMESPACE"
        git push
    }
    popd
    rm -fR infra
}
popd

# Export Terraform Output as Environment Variables
$(CLUSTER_NAMESPACE=$CLUSTER_NAMESPACE python ./utils/terraform_make_env.py < ./terraform/output.json)

# Create and Commit Namespace Infrastructure
pushd /tmp
{
    git clone $STATE_REPO state
    pushd state
    {
        sed 's|$(CLUSTER_NAMESPACE)|'"$CLUSTER_NAMESPACE"'|g' $BASE/k8s/namespace.yaml > namespace.yaml
        git add -A
        git commit -sm "feat(ArgoCD): Namespace"
        git push
    }
    popd
    rm -fR state
}

# Setup ArgoCD Namespace Repository
while [ "${ARGOCD_PORT:-0}" -le 1024 ]
do
    ARGOCD_PORT=$RANDOM
done
kubectl port-forward svc/argocd-server -n argocd $ARGOCD_PORT:443 & PORTFORWARD_PID=$!
ARGOCD_PASSWORD=$(kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2)
until nc -z localhost $ARGOCD_PORT
do
    sleep 1
done
argocd login localhost:$ARGOCD_PORT --insecure --username admin --password $ARGOCD_PASSWORD
argocd repo add $STATE_REPO --ssh-private-key-path $TMPDIR/id_rsa

# Commit ArgoCD Namespace Setup
pushd /tmp
{
    git clone git@github.com:$GITHUB_ORGANIZATION/$CLUSTER_NAME-STATE-argocd.git argocd
    pushd argocd
    {
        sed -i '' 's|$(GIT_REPOSITORY)|'"$STATE_REPO"'|g' $BASE/argocd/application.yaml
        sed -i '' 's|$(CLUSTER_NAMESPACE)|'"$CLUSTER_NAMESPACE"'|g' $BASE/argocd/application.yaml
        cp -R $BASE/argocd/application.yaml $CLUSTER_NAMESPACE.yaml
        sed -i '' 's|$(CLUSTER_NAMESPACE)|'"$CLUSTER_NAMESPACE"'|g' $BASE/argocd/kustomization.yaml.patch
        git apply $BASE/argocd/kustomization.yaml.patch
        git add -A
        git commit -sm "feat(ArgoCD): $CLUSTER_NAMESPACE"
        git push
    }
    popd
    rm -fR argocd
}
popd

# git stash -a
