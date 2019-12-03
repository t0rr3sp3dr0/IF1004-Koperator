output "cluster_name" {
  value = var.cluster_name
}

output "infra_repo" {
  value = github_repository.cluster_infra.ssh_clone_url
}

output "state_repo" {
  value = github_repository.cluster_state_argocd.ssh_clone_url
}
