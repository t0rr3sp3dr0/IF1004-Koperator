resource "github_repository" "cluster_infra" {
  name = "${var.cluster_name}-INFRA"
}

resource "github_repository" "cluster_state_argocd" {
  name = "${var.cluster_name}-STATE-argocd"
}
