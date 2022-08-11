terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.12.1"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "multinode-demo"
}

resource "kubernetes_namespace" "example" {
  metadata {
    name = "gitlab-runner"
  }
}
resource "kubernetes_config_map" "gitlab_runner_config" {
  metadata {
    name      = "gitlab-runner-config"
    namespace = "gitlab-runner"
  }

  data = {
    "config.toml" = "concurrent = 4\n[[runners]]\n  name = \"Kubernetes Demo Runner\"\n  url = \"https://gitlab.com/\"\n  token = \"iJkQvKsiKVaJNhfvXnoxJC4ZYUM3izURZoPAV4y8Snw6yYcM6g\"\n  executor = \"kubernetes\"\n  [runners.kubernetes]\n    namespace = \"gitlab-runner\"\n    poll_timeout = 600\n    cpu_request = \"1\"\n    service_cpu_request = \"200m\"\n    [[runners.kubernetes.volumes.host_path]]\n        name = \"docker\"\n        mount_path = \"/var/run/docker.sock\"\n        host_path = \"/var/run/docker.sock\""
  }
}

resource "kubernetes_deployment" "gitlab_runner" {

  depends_on = [
    kubernetes_manifest.service_account
  ]
  metadata {
    name      = "gitlab-runner"
    namespace = "gitlab-runner"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        name = "gitlab-runner"
      }
    }

    template {
      metadata {
        labels = {
          name = "gitlab-runner"
        }
      }

      spec {
        volume {
          name = "config"

          config_map {
            name = "gitlab-runner-config"
          }
        }

        container {
          name  = "gitlab-runner"
          image = "gitlab/gitlab-runner:latest"
          args  = ["run"]

          resources {
            limits = {
              cpu = "100m"
            }

            requests = {
              cpu = "100m"
            }
          }

          volume_mount {
            name       = "config"
            read_only  = true
            mount_path = "/etc/gitlab-runner/config.toml"
            sub_path   = "config.toml"
          }

          image_pull_policy = "Always"
        }

        restart_policy       = "Always"
        service_account_name = "gitlab-admin"
      }
    }
  }
}

# resource "kubernetes_service_account" "gitlab_admin" {
#   metadata {
#     name      = "gitlab-admin"
#     namespace = "gitlab-runner"
#   }
# }

resource "kubernetes_manifest" "service_account" {
  manifest = {
    "apiVersion" = "v1"
    "kind"       = "ServiceAccount"
    "metadata" = {
      "namespace" = "gitlab-runner"
      "name"      = "gitlab-admin"
    }

    "automountServiceAccountToken" = true
    "imagePullSecrets" = [
      {
        "name" = "image-pull-secret"
      },
    ]
  }
}
resource "kubernetes_role" "gitlab_admin" {
  metadata {
    name      = "gitlab-admin"
    namespace = "gitlab-runner"
  }

  rule {
    verbs      = ["*"]
    api_groups = [""]
    resources  = ["*"]
  }
}

resource "kubernetes_role_binding" "gitlab_admin" {
  metadata {
    name      = "gitlab-admin"
    namespace = "gitlab-runner"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "gitlab-admin"
    namespace = "gitlab-runner"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "gitlab-admin"
  }
}

resource "kubernetes_cluster_role" "gitlab_admin_global" {
  metadata {
    name = "gitlab-admin-global"
  }

  rule {
    verbs      = ["*"]
    api_groups = ["*"]
    resources  = ["*"]
  }
}

resource "kubernetes_cluster_role_binding" "gitlab_admin_2" {
  metadata {
    name = "gitlab-admin-2"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "gitlab-admin"
    namespace = "gitlab-runner"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "gitlab-admin-global"
  }
}
