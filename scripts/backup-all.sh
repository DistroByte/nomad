#!/bin/bash

echo "backup vikunja"
./backup-vikunja.sh
echo "backup hedgedoc"
./backup-hedgedoc.sh
echo "backup postgres"
./backup-postgres.sh
echo "backup paperless"
./backup-paperless.sh >/dev/null
