job "wger" {
    datacenters = ["dc1"]
    type        = "service"

    group "web" {
        network {
            port "http" {
                to = 8000
            }
            port "cache" {
                static = 6379
            }
        }

        service {
            name = "wger"
            port = "http"

            check {
                type     = "http"
                path     = "/"
                interval = "10s"
                timeout  = "2s"
            }

            tags = [
                "traefik.enable=true",
                "traefik.http.routers.wger.rule=Host(`wger.dbyte.xyz`)",
                "traefik.http.routers.wger.entrypoints=websecure",
                "traefik.http.routers.wger.tls.certresolver=lets-encrypt",
		"prometheus.io/scrape=false"
            ]
        }

        task "wger-server" {
            driver = "docker"

            config {
                image = "wger/server:latest"
                ports = ["http"]

                volumes = [
                    "/data/wger/media:/home/wger/media",
                    "/data/wger/static:/home/wger/static"
                ]
            }

            template {
                data = <<EOF
# Django's secret key, change to a 50 character random string if you are running
# this instance publicly. For an online generator, see e.g. https://djecrety.ir/
SECRET_KEY=$=7k0)&bwcpcl#$gdd*4)4lpqzjd^2b5y*g_3*xwk_y97iz2c0

# Signing key used for JWT, use something different than the secret key
SIGNING_KEY=sk4!y@^k0s#v5a9qt7^htd*v!svo#9%8nx04g$66di$u4e+sv5

# The server's timezone, for a list of possible names:
# https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
TIME_ZONE=Europe/Dublin


# CSRF_TRUSTED_ORIGINS=https://wger.dbyte.xyz,https://118.999.881.119
# X_FORWARDED_PROTO_HEADER_SET=True

MEDIA_URL=https://wger.dbyte.xyz/media/
STATIC_URL=https://wger.dbyte.xyz/static/

#
# These settings usually don't need changing
#

#
# Application
WGER_INSTANCE=https://wger.de # Wger instance from which to sync exercises, images, etc.
ALLOW_REGISTRATION=False
ALLOW_GUEST_USERS=False
ALLOW_UPLOAD_VIDEOS=True
# Users won't be able to contribute to exercises if their account age is
# lower than this amount in days.
MIN_ACCOUNT_AGE_TO_TRUST=21
# Synchronzing exercises
# It is recommended to keep the local database synchronized with the wger
# instance specified in WGER_INSTANCE since there are new added or translations
# improved. For this you have different possibilities:
# - Sync exercises on startup:
SYNC_EXERCISES_ON_STARTUP=True
DOWNLOAD_EXERCISE_IMAGES_ON_STARTUP=True
# - Sync them in the background with celery. This will setup a job that will run
#   once a week at a random time (this time is selected once when starting the server)
SYNC_EXERCISES_CELERY=False
SYNC_EXERCISE_IMAGES_CELERY=False
SYNC_EXERCISE_VIDEOS_CELERY=False
# - Manually trigger the process as needed:
#   docker compose exec web python3 manage.py sync-exercises
#   docker compose exec web python3 manage.py download-exercise-images
#   docker compose exec web python3 manage.py download-exercise-videos

# Synchronzing ingredients
# You can also syncronize the ingredients from a remote wger instance, and have
# basically the same options as for the ingredients:
# - Sync them in the background with celery. This will setup a job that will run
#   once a week at a random time (this time is selected once when starting the server)
SYNC_INGREDIENTS_CELERY=False
# - Manually trigger the process as needed:
#   docker compose exec web python3 manage.py sync-ingredients

DOWNLOAD_INGREDIENTS_FROM=WGER

# Whether celery is configured and should be used. Can be left to true with
# this setup but can be deactivated if you are using the app in some other way
USE_CELERY=False

#
# Celery
# CELERY_BROKER=redis://cache:6379/2
# CELERY_BACKEND=redis://cache:6379/2
# CELERY_FLOWER_PASSWORD=adminadmin

#
# Database
DJANGO_DB_ENGINE=django.db.backends.postgresql
DJANGO_DB_DATABASE=wger
DJANGO_DB_USER=wger
DJANGO_DB_PASSWORD={{ key "wger/db/pass" }}
DJANGO_DB_HOST=postgresql.service.consul
DJANGO_DB_PORT=5432
DJANGO_PERFORM_MIGRATIONS=True # Perform any new database migrations on startup

#
# Cache
DJANGO_CACHE_BACKEND=django_redis.cache.RedisCache
DJANGO_CACHE_LOCATION=redis://wger-cache:6379/1
DJANGO_CACHE_TIMEOUT=1296000 # in seconds - 60*60*24*15, 15 Days
DJANGO_CACHE_CLIENT_CLASS=django_redis.client.DefaultClient

#
# Brute force login attacks
# https://django-axes.readthedocs.io/en/latest/index.html
AXES_ENABLED=True
AXES_FAILURE_LIMIT=10
AXES_COOLOFF_TIME=30 # in minutes
AXES_HANDLER=axes.handlers.cache.AxesCacheHandler
AXES_LOCKOUT_PARAMETERS=ip_address
AXES_IPWARE_PROXY_COUNT=1
AXES_IPWARE_META_PRECEDENCE_ORDER=HTTP_X_FORWARDED_FOR,REMOTE_ADDR
#
# Others
DJANGO_DEBUG=True
WGER_USE_GUNICORN=True
EXERCISE_CACHE_TTL=18000 # in seconds - 5*60*60, 5 hours
SITE_URL=http://localhost

#
# JWT auth
ACCESS_TOKEN_LIFETIME=10 # The lifetime duration of the access token, in minutes
REFRESH_TOKEN_LIFETIME=24 # The lifetime duration of the refresh token, in hours

#
# Other possible settings

# RECAPTCHA_PUBLIC_KEY
# RECAPTCHA_PRIVATE_KEY
# NOCAPTCHA

DJANGO_CLEAR_STATIC_FIRST=False

#
# Email
# https://docs.djangoproject.com/en/4.1/topics/email/#smtp-backend
# ENABLE_EMAIL=False
# EMAIL_HOST=email.example.com
# EMAIL_PORT=587
# EMAIL_HOST_USER=username
# EMAIL_HOST_PASSWORD=password
# EMAIL_USE_TLS=True
# EMAIL_USE_SSL=False
FROM_EMAIL='wger Workout Manager <wger@example.com>'
EOF

                destination = "local/env"
                env         = true
            }
        }

        task "cache" {
            driver = "docker"

            config {
                image = "redis:latest"
                ports = ["cache"]

                volumes = [
                    "/data/wger/media:/home/wger/media",
                    "/data/wger/static:/home/wger/static"
                ]
            }

            service {
                name = "wger-cache"
                port = "cache"
            }
        }
    }
}
