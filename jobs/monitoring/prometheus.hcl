job "prometheus" {
  datacenters = ["dc1"]


  group "prometheus" {
    network {
      port "http" {
        static = 9090
      }
    }

    service {
      name = "prometheus"
      port = "http"

      tags = [
        "traefik.enable=false",
        "traefik.http.routers.prometheus.rule=Host(`prometheus.dbyte.xyz`)",
      ]

      check {
        type     = "http"
        path     = "/-/healthy"
        interval = "10s"
        timeout  = "2s"

        success_before_passing   = "3"
        failures_before_critical = "3"

        check_restart {
          limit = 3
          grace = "60s"
        }
      }
    }

    volume "prometheus" {
      type            = "csi"
      source          = "prometheus"
      read_only       = false
      attachment_mode = "file-system"
      access_mode     = "single-node-writer"
    }

    task "prometheus" {
      driver = "docker"
      user = "0"
      config {
        image = "quay.io/prometheus/prometheus"
        ports = ["http"]

        args = [
          "--config.file=/etc/prometheus/config/prometheus.yml",
          "--log.level=info",
          "--storage.tsdb.retention.time=90d",
          "--storage.tsdb.retention.size=30GB",
          "--storage.tsdb.path=/prometheus",
          "--web.console.libraries=/usr/share/prometheus/console_libraries",
          "--web.console.templates=/usr/share/prometheus/consoles"
        ]

        volumes = [
          "local/config:/etc/prometheus/config",
        ]
      }

      volume_mount {
        volume      = "prometheus"
        destination = "/prometheus"
      }

      artifact {
        source      = "https://raw.githubusercontent.com/geerlingguy/internet-pi/master/internet-monitoring/prometheus/alert.rules"
        destination = "local/config/"
      }

      template {
        data = <<EOH
---
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  scrape_timeout: 10s
  external_labels:
    monitor: 'Alertmanager'

rule_files:
  - 'alert.rules'

scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:{{env "NOMAD_PORT_http"}}']

  - job_name: nomad
    metrics_path: '/v1/metrics'
    params:
      format: ['prometheus']
    consul_sd_configs:
    - server: 'consul.service.consul:8500'
      datacenter: 'dc1'
      scheme: 'http'
      services: ['nomad-client', 'nomad']
      tags: ['http']

  - job_name: consul
    metrics_path: '/v1/agent/metrics'
    params:
      format: ['prometheus']
    scheme: 'http'
    static_configs:
    - targets:
        [
          {{range $index, $service := service "consul" "any"}}{{if ne $index 0}}, {{end}}'{{.Address}}:8500'{{end}}
        ]

  - job_name: 'pihole'
    consul_sd_configs:
    - server: 'consul.service.consul:8500'
      datacenter: 'dc1'
      scheme: 'http'
      services: ['prometheus-pihole-exporter']

  - job_name: 'nodeexp'
    static_configs:
    consul_sd_configs:
    - server: 'consul.service.consul:8500'
      datacenter: 'dc1'
      scheme: 'http'
      services: ['node-exporter']

  - job_name: 'ghost-photo'
    static_configs:
    consul_sd_configs:
    - server: 'consul.service.consul:8500'
      datacenter: 'dc1'
      scheme: 'http'
      services: ['photo']
EOH

        change_mode   = "signal"
        change_signal = "SIGHUP"
        destination   = "local/config/prometheus.yml"
      }

    }
  }
}
