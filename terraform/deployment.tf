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

### Deployment
resource "kubernetes_deployment" "nginx_hello_deployment" {
  metadata {
    name = "nginx-hello-deployment"
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "nginx-hello"
      }
    }

    template {
      metadata {
        labels = {
          app = "nginx-hello"
        }
      }

      spec {
        volume {
          name = "config-volume"

          config_map {
            name = "nginx-hello-configmap"
          }
        }

        container {
          name  = "nginx-hello"
          image = "nginxdemos/hello"

          port {
            container_port = 80
          }

          resources {
            limits = {
              cpu = "200m"

              memory = "256Mi"
            }

            requests = {
              cpu = "100m"

              memory = "128Mi"
            }
          }

          volume_mount {
            name       = "config-volume"
            mount_path = "/etc/nginx/conf.d/hello.conf"
            sub_path   = "hello.conf"
          }

          liveness_probe {
            http_get {
              path = "/status/live"
              port = "80"
            }

            initial_delay_seconds = 3
            timeout_seconds       = 1
          }

          readiness_probe {
            http_get {
              path = "/status/ready"
              port = "80"
            }

            initial_delay_seconds = 3
            timeout_seconds       = 1
          }

          image_pull_policy = "IfNotPresent"
        }

        topology_spread_constraint {
          max_skew           = 1
          topology_key       = "kubernetes.io/hostname"
          when_unsatisfiable = "ScheduleAnyway"

          label_selector {
            match_labels = {
              app = "nginx-hello"
            }
          }
        }
      }
    }
  }
}

### ConfigMap
resource "kubernetes_config_map" "nginx_hello_configmap" {
  metadata {
    name = "nginx-hello-configmap"
  }

  data = {
    "hello.conf" = "${file("${path.module}/hello.conf")}"
  }
}

### Service
resource "kubernetes_service" "nginx_hello_service" {
  metadata {
    name = "nginx-hello-service"
  }

  spec {
    port {
      protocol    = "TCP"
      port        = 30001
      target_port = "80"
      node_port   = 30001
    }

    selector = {
      app = "nginx-hello"
    }

    type = "NodePort"
  }
}

### HPA
resource "kubernetes_horizontal_pod_autoscaler" "nginx_hpa_resource_metrics_cpu" {
  metadata {
    name = "nginx-hpa-resource-metrics-cpu"
  }

  spec {
    scale_target_ref {
      kind        = "Deployment"
      name        = "nginx-hello-deployment"
      api_version = "apps/v1"
    }

    min_replicas = 2
    max_replicas = 6

    metric {
      type = "Resource"

      resource {
        name = "cpu"

        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
  }
}

### Service Account
resource "kubernetes_service_account" "nginx_service_account" {
  metadata {
    name = "nginx-service-account"
  }
}

### Role
resource "kubernetes_role" "nginx_service_configmap_access_role" {
  metadata {
    name = "nginx-service-configmap-access-role"
  }

  rule {
    verbs      = ["get"]
    api_groups = [""]
    resources  = ["configmaps"]
  }
}

### Role Binding
resource "kubernetes_role_binding" "nginx_service_configmap_access_rolebinding" {
  metadata {
    name = "nginx-service-configmap-access-rolebinding"
  }

  subject {
    kind = "ServiceAccount"
    name = "nginx-service-account"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "nginx-service-configmap-access-role"
  }
}

