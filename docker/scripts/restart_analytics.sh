#!/bin/sh

cd `dirname $0`

# Analytics build container (currently hosted on mega3)
./restart_jenkinsdocker.py ceejatec/ubuntu-1404-analytics-build:20160901 analytics-01 2412 server.jenkins.couchbase.com &

wait
echo "All done!"

