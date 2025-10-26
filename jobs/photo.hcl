job "photo" {
  datacenters = ["dc1"]

  type = "service"

  group "web" {
    count = 1

    update {
      max_parallel      = 1
      min_healthy_time  = "10s"
      healthy_deadline  = "5m"
      progress_deadline = "8m"
      auto_revert       = true
      auto_promote      = false
    }

    restart {
      attempts = 3
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    network {
      port "http" {
        to = 2368
      }
      port "metrics-http" {
        to = 3000
      }
    }

    volume "photo-data" {
      type            = "csi"
      read_only       = false
      source          = "photo"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }

    ephemeral_disk {
      size    = 300
      migrate = true
    }

    service {
      name = "photo"
      port = "http"

      check {
        type     = "tcp"
        interval = "15s"
        timeout  = "5s"

        success_before_passing   = "1"
        failures_before_critical = "2"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.photo.rule=Host(`photo.james-hackett.ie`) || Host(`admin-photo.james-hackett.ie`)",
        "icon=https://photo.james-hackett.ie/content/images/size/w256h256/2025/03/J_Profile_Picture_Round.png",
      ]
    }

    task "website" {
      driver = "docker"

      config {
        image      = "ghost:latest"
        ports      = ["http"]
        entrypoint = ["/local/ghost-with-tinybird.sh"]
      }

      volume_mount {
        volume      = "photo-data"
        destination = "/var/lib/ghost/content"
        read_only   = false
      }

      template {
        data        = <<EOF
#!/bin/bash
set -euo pipefail

# Start Ghost in the background first for faster startup
echo "Starting Ghost..."
docker-entrypoint.sh node current/index.js &
GHOST_PID=$!

# Run Tinybird setup in background while Ghost starts
echo "Setting up Tinybird CLI in background..."
(
  # Install dependencies for Tinybird CLI silently
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq --no-install-recommends \
      curl \
      jq \
      ca-certificates \
      python3 \
      python3-pip \
      >/dev/null 2>&1 && rm -rf /var/lib/apt/lists/* >/dev/null 2>&1

  # Install Tinybird CLI
  echo "Installing Tinybird CLI..."
  export TB_CLI_TELEMETRY_OPTOUT=1
  curl -s https://tinybird.co | sh >/dev/null 2>&1
  export PATH="/root/.local/bin:$PATH"

  # Test Tinybird authentication
  echo "Testing Tinybird authentication..."
  if tb --cloud --host "${TINYBIRD_API_URL}" --token "${TINYBIRD_ADMIN_TOKEN}" workspace ls >/dev/null 2>&1; then
      echo "Tinybird authentication successful!"
      
      # Look for Ghost's built-in Tinybird files
      TINYBIRD_PATH="/var/lib/ghost/current/core/server/data/tinybird"
      if [[ -d "$TINYBIRD_PATH" ]]; then
          echo "Found Ghost's Tinybird analytics files, running deployment..."
          
          # Save current directory and change to Tinybird path
          ORIGINAL_DIR=$(pwd)
          cd "$TINYBIRD_PATH"
          
          # Run Tinybird deployment
          echo "Deploying Tinybird analytics schema..."
          if tb --cloud --host "${TINYBIRD_API_URL}" --token "${TINYBIRD_ADMIN_TOKEN}" deploy --wait >/dev/null 2>&1; then
              echo "Tinybird analytics deployment completed successfully!"
          else
              echo "Warning: Tinybird deployment failed, but Ghost continues running..."
          fi
          
          # Return to original directory
          cd "$ORIGINAL_DIR"
      else
          echo "No Tinybird analytics files found - Ghost continues without analytics setup"
      fi
  else
      echo "Warning: Tinybird authentication failed - Ghost continues without analytics"
  fi
) &

# Wait for Ghost process
wait $GHOST_PID
EOF
        destination = "local/ghost-with-tinybird.sh"
        perms       = "755"
      }

      template {
        data        = <<EOF
url="https://{{ key "ghost/domain" }}"
admin__url="https://{{ key "ghost/admin_domain" }}"
database__client="sqlite3"
database__connection__filename="/var/lib/ghost/content/data/ghost.db"
logging__level="info"
logging__transports="[\"stdout\"]"
mail__from="support@photo.james-hackett.ie"
security__staffDeviceVerification="false"
mail__transport="SMTP"
mail__options__service="Mailgun"
mail__options__host="smtp.eu.mailgun.org"
mail__options__port="465"
mail__options__secure="true"
mail__options__auth__user="{{ key "ghost/mail/auth/user" }}"
mail__options__auth__pass="{{ key "ghost/mail/auth/pass" }}"
tinybird__tracker__endpoint="https://{{ key "ghost/domain" }}/.ghost/analytics/api/v1/page_hit"
tinybird__stats__endpoint="{{ key "ghost/tinybird/api_url" }}"
tinybird__adminToken="{{ key "ghost/tinybird/admin_token" }}"
tinybird__workspaceId="{{ key "ghost/tinybird/workspace_id" }}"
tinybird__tracker__datasource="analytics_events"
TINYBIRD_API_URL="{{ key "ghost/tinybird/api_url" }}"
TINYBIRD_WORKSPACE_ID="{{ key "ghost/tinybird/workspace_id" }}"
TINYBIRD_ADMIN_TOKEN="{{ key "ghost/tinybird/admin_token" }}"
EOF
        destination = "local/ghost.env"
        env         = true
      }

      resources {
        cpu    = 650
        memory = 1000
      }
    }

    task "analytics" {
      driver = "docker"

      config {
        image = "ghost/traffic-analytics:1.0.20"
        ports = ["metrics-http"]
      }

      template {
        data        = <<EOF
NODE_ENV="production"
PROXY_TARGET="{{ key "ghost/tinybird/api_url" }}/v0/events"
SALT_STORE_TYPE="file"
SALT_STORE_FILE_PATH="/alloc/data/salts.json"
TINYBIRD_TRACKER_TOKEN="{{ key "ghost/tinybird/tracker_token" }}"
LOG_LEVEL="trace"
EOF
        destination = "local/analytics.env"
        env         = true
      }

      service {
        name = "photo-analytics"
        port = "metrics-http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.photo-analytics.rule=Host(`photo.james-hackett.ie`) && PathRegexp(`^(.*)/\\.ghost/analytics(.*)$`)",
          "traefik.http.middlewares.photo-analytics-rewrite.replacepathregex.regex=^(.*)/\\.ghost/analytics(.*)$",
          "traefik.http.middlewares.photo-analytics-rewrite.replacepathregex.replacement=$2",
          "traefik.http.routers.photo-analytics.middlewares=photo-analytics-rewrite",
          "traefik.http.routers.photo-analytics.priority=100",
          "molecule.skip=true"
        ]
      }

      resources {
        cpu    = 100
        memory = 300
      }

      # Kill timeout for graceful shutdown  
      kill_timeout = "15s"
    }
  }
}
