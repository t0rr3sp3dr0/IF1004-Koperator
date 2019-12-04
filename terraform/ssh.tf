resource "github_repository_deploy_key" "cluster_state_argocd" {
  repository = github_repository.cluster_state_argocd.name
  title      = "ArgoCD"
  key        = var.state_argocd_key
  read_only  = "true"
}
