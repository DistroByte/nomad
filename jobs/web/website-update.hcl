job "website-update" {
  datacenters = ["dc1"]
  type        = "batch"

  periodic {
    cron             = "0 0 * * * *"
    prohibit_overlap = true
  }

  group "website-update" {  
    task "update-site" {
      driver = "raw_exec"

      config {
        command = "/bin/bash"
        args    = ["local/script.sh"]
      }

      template {
        data = <<EOH
#/bin/bash

mv /data/website/site/index.html{,.bak}

wget https://flowcv.me/james-hackett -qO /data/website/site/index.html

if [ -s /data/website/site/index.html ]; then
  sed -i 's/<img src="[^>]*" alt="James Hackett" class="sc-gsDKAQ WjBEv">/<img src=".\/profile.webp" alt="James Hackett" class="sc-gsDKAQ WjBEv">/g' /data/website/site/index.html
  sed -i 's|<script data-cfasync="false" src="/cdn-cgi/scripts/5c5dd728/cloudflare-static/email-decode.min.js"></script>|<script data-cfasync="false" src="https://flowcv.io/cdn-cgi/scripts/5c5dd728/cloudflare-static/email-decode.min.js"></script>|' /data/website/site/index.html
  sed -i '/<head>/a <script defer data-domain="james-hackett.ie" src="https://plausible.dbyte.xyz/js/script.js"></script>' /data/website/site/index.html
  echo "$(date) - updated successfully"
else
  mv /data/website/site/index.html{.bak,}
  echo "$(date) - update unsuccessful"
fi
EOH
        destination = "local/script.sh"
      }
    }
  }
}
