job "glances" {
  datacenters = ["dc1"]
  type = "system"
  
  group "web" {
    network {
      mode = "host"

      port "http" {
	static = "61208"
      }
    }

    service {
      name = "glances"

      tags = [
	"traefik.port=61208",
        "traefik.frontend.rule=Host:glances.docker.localhost"
      ]
    }

    task "glances" {
      driver = "docker"

      config {
        image = "nicolargo/glances:dev"
	privileged = true
        ports = ["http"]
	pid_mode = "host"
	volumes = [
	  "local/glances.conf:/glances/conf/glances.conf"
	]
      }
      
      env {
	GLANCES_OPT = "-C /glances/conf/glances.conf -w"
      }

      resources {
        cpu = 20
	memory = 100
      }

      template {
	data = <<EOH
##############################################################################
# Globals Glances parameters
##############################################################################

[global]
# Stats refresh rate (default is a minimum of 2 seconds)
# Can be overwrite by the -t <sec> option
# It is also possible to overwrite it in each plugin sections
refresh=2
# Does Glances should check if a newer version is available on PyPI ?
check_update=true
# History size (maximum number of values)
# Default is 1200 values (~1h with the default refresh rate)
history_size=1200
# Set the way Glances should display the date (default is %Y-%m-%d %H:%M:%S %Z)
#strftime_format="%Y-%m-%d %H:%M:%S %Z"

##############################################################################
# User interface
##############################################################################

[outputs]
# Theme name for the Curses interface: black or white
curse_theme=black
# Limit the number of processes to display in the WebUI
max_processes_display=30

##############################################################################
# plugins
##############################################################################

[quicklook]
# Set to true to disable a plugin
# Note: you can also disable it from the command line (see --disable-plugin <plugin_name>)
disable=False
# Graphical percentage char used in the terminal user interface (default is |)
percentage_char=|
# Define CPU, MEM and SWAP thresholds in %
cpu_careful=50
cpu_warning=70
cpu_critical=90
mem_careful=50
mem_warning=70
mem_critical=90
swap_careful=50
swap_warning=70
swap_critical=90

[system]
# This plugin display the first line in the Glances UI with:
# Hostname / Operating system name / Architecture information
# Set to true to disable a plugin
disable=False
# Default refresh rate is 60 seconds
#refresh=60

[cpu]
disable=False
# See https://scoutapm.com/blog/slow_server_flow_chart
#
# I/O wait percentage should be lower than 1/# (# = Logical CPU cores)
# Leave commented to just use the default config:
# Careful=1/#*100-20% / Warning=1/#*100-10% / Critical=1/#*100
#iowait_careful=30
#iowait_warning=40
#iowait_critical=50
#
# Total % is 100 - idle
total_careful=65
total_warning=75
total_critical=85
total_log=True
#
# Default values if not defined: 50/70/90 (except for iowait)
user_careful=50
user_warning=70
user_critical=90
user_log=False
#
system_careful=50
system_warning=70
system_critical=90
system_log=False
#
steal_careful=50
steal_warning=70
steal_critical=90
#steal_log=True
#
# Context switch limit (core / second)
# Leave commented to just use the default config (critical is 50000*# (Logical CPU cores)
#ctx_switches_careful=10000
#ctx_switches_warning=12000
#ctx_switches_critical=14000

[percpu]
disable=False
# Define CPU thresholds in %
# Default values if not defined: 50/70/90
user_careful=50
user_warning=70
user_critical=90
iowait_careful=50
iowait_warning=70
iowait_critical=90
system_careful=50
system_warning=70
system_critical=90

[gpu]
disable=False
# Default processor values if not defined: 50/70/90
proc_careful=50
proc_warning=70
proc_critical=90
# Default memory values if not defined: 50/70/90
mem_careful=50
mem_warning=70
mem_critical=90

[mem]
disable=False
# Define RAM thresholds in %
# Default values if not defined: 50/70/90
careful=50
warning=70
critical=90

[memswap]
disable=False
# Define SWAP thresholds in %
# Default values if not defined: 50/70/90
careful=50
warning=70
critical=90

[load]
disable=False
# Define LOAD thresholds
# Value * number of cores
# Default values if not defined: 0.7/1.0/5.0 per number of cores
# Source: http://blog.scoutapp.com/articles/2009/07/31/understanding-load-averages
#         http://www.linuxjournal.com/article/9001
careful=0.7
warning=1.0
critical=5.0
#log=False

[network]
disable=False
# Default bitrate thresholds in % of the network interface speed
# Default values if not defined: 70/80/90
rx_careful=70
rx_warning=80
rx_critical=90
tx_careful=70
tx_warning=80
tx_critical=90
# Define the list of hidden network interfaces (comma-separated regexp)
#hide=docker.*,lo
# Define the list of wireless network interfaces to be show (comma-separated)
#show=docker.*
# WLAN 0 alias
#wlan0_alias=Wireless
# It is possible to overwrite the bitrate thresholds per interface
# WLAN 0 Default limits (in bits per second aka bps) for interface bitrate
#wlan0_rx_careful=4000000
#wlan0_rx_warning=5000000
#wlan0_rx_critical=6000000
#wlan0_rx_log=True
#wlan0_tx_careful=700000
#wlan0_tx_warning=900000
#wlan0_tx_critical=1000000
#wlan0_tx_log=True

[ip]
disable=False
public_refresh_interval=300
public_ip_disabled=False
# Configuration for the Censys online service
# Need to create an aacount: https://censys.io/login
censys_url=https://search.censys.io/api
# Get your own credential here: https://search.censys.io/account/api
# Enter your credential and uncomment the following lines
#censys_username=<censys_api_id>
#censys_password=<censys_secret>
# List of fields to be displayed in user interface (comma separated)
censys_fields=location:continent,location:country,autonomous_system:name

[connections]
# Display additional information about TCP connections
# This plugin is disabled by default
disable=True
# nf_conntrack thresholds in %
nf_conntrack_percent_careful=70
nf_conntrack_percent_warning=80
nf_conntrack_percent_critical=90

[wifi]
disable=True
# Define the list of hidden wireless network interfaces (comma-separated regexp)
hide=lo,docker.*
# Define the list of wireless network interfaces to be show (comma-separated)
#show=docker.*
# Define SIGNAL thresholds in db (lower is better...)
# Based on: http://serverfault.com/questions/501025/industry-standard-for-minimum-wifi-signal-strength
careful=-65
warning=-75
critical=-85

[diskio]
disable=False
# Define the list of hidden disks (comma-separated regexp)
#hide=sda2,sda5,loop.*
hide=loop.*,/dev/loop.*
# Define the list of disks to be show (comma-separated)
#show=sda.*
# Alias for sda1
#sda1_alias=InternalDisk

[fs]
disable=False
# Define the list of file system to hide (comma-separated regexp)
hide=/boot.*,/snap.*
# Define the list of file system to show (comma-separated regexp)
#show=/,/srv
# Define filesystem space thresholds in %
# Default values if not defined: 50/70/90
# It is also possible to define per mount point value
# Example: /_careful=40
careful=50
warning=70
critical=90
# Allow additional file system types (comma-separated FS type)
#allow=shm

[irq]
# Documentation: https://glances.readthedocs.io/en/latest/aoa/irq.html
# This plugin is disabled by default
disable=True

[folders]
# Documentation: https://glances.readthedocs.io/en/latest/aoa/folders.html
disable=False
# Define a folder list to monitor
# The list is composed of items (list_#nb <= 10)
# An item is defined by:
# * path: absolute path
# * careful: optional careful threshold (in MB)
# * warning: optional warning threshold (in MB)
# * critical: optional critical threshold (in MB)
# * refresh: interval in second between two refreshes
#folder_1_path=/tmp
#folder_1_careful=2500
#folder_1_warning=3000
#folder_1_critical=3500
#folder_1_refresh=60
#folder_2_path=/home/nicolargo/Videos
#folder_2_warning=17000
#folder_2_critical=20000
#folder_3_path=/nonexisting
#folder_4_path=/root

[cloud]
# Documentation: https://glances.readthedocs.io/en/latest/aoa/cloud.html
# This plugin is disabled by default
disable=True

[raid]
# Documentation: https://glances.readthedocs.io/en/latest/aoa/raid.html
# This plugin is disabled by default
disable=True

[smart]
# Documentation: https://glances.readthedocs.io/en/latest/aoa/smart.html
# This plugin is disabled by default
disable=True

[hddtemp]
disable=False
# Define hddtemp server IP and port (default is 127.0.0.1 and 7634 (TCP))
host=127.0.0.1
port=7634

[sensors]
# Documentation: https://glances.readthedocs.io/en/latest/aoa/sensors.html
disable=False
# By default refresh every refresh time * 2
#refresh=6
# Hide some sensors
#hide=ambient
# Sensors core thresholds (in Celsius...)
# Default values are grabbed from the system
#temperature_core_careful=60
#temperature_core_warning=70
#temperature_core_critical=80
# Temperatures threshold in °C for hddtemp
# Default values if not defined: 45/52/60
temperature_hdd_careful=45
temperature_hdd_warning=52
temperature_hdd_critical=60
# Battery threshold in %
battery_careful=80
battery_warning=90
battery_critical=95
# Sensors alias
#temp1_alias=Motherboard 0
#temp2_alias=Motherboard 1
#core 0_temperature_core_alias=CPU Core 0 temp
#core 0_fans_speed_alias=CPU Core 0 fan
#or
#core 0_alias=CPU Core 0
#core 1_alias=CPU Core 1

[processcount]
disable=False
# If you want to change the refresh rate of the processing list, please uncomment:
#refresh=10

[processlist]
disable=False
# Sort key: if not defined, the sort is automatically done by Glances (recommended)
# Should be one of the following:
# cpu_percent, memory_percent, io_counters, name, cpu_times, username
#sort_key=memory_percent
# Define CPU/MEM (per process) thresholds in %
# Default values if not defined: 50/70/90
cpu_careful=50
cpu_warning=70
cpu_critical=90
mem_careful=50
mem_warning=70
mem_critical=90
#
# Nice priorities range from -20 to 19.
# Configure nice levels using a comma separated list.
#
# Nice: Example 1, non-zero is warning (default behavior)
nice_warning=-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
#
# Nice: Example 2, low priority processes escalate from careful to critical
#nice_careful=1,2,3,4,5,6,7,8,9
#nice_warning=10,11,12,13,14
#nice_critical=15,16,17,18,19

[ports]
disable=False
# Interval in second between two scans
# Ports scanner plugin configuration
refresh=30
# Set the default timeout (in second) for a scan (can be overwritten in the scan list)
timeout=3
# If port_default_gateway is True, add the default gateway on top of the scan list
port_default_gateway=True
#
# Define the scan list (1 < x < 255)
# port_x_host (name or IP) is mandatory
# port_x_port (TCP port number) is optional (if not set, use ICMP)
# port_x_description is optional (if not set, define to host:port)
# port_x_timeout is optional and overwrite the default timeout value
# port_x_rtt_warning is optional and defines the warning threshold in ms
#
#port_1_host=192.168.0.1
#port_1_port=80
#port_1_description=Home Box
#port_1_timeout=1
#port_2_host=www.free.fr
#port_2_description=My ISP
#port_3_host=www.google.com
#port_3_description=Internet ICMP
#port_3_rtt_warning=1000
#port_4_description=Internet Web
#port_4_host=www.google.com
#port_4_port=80
#port_4_rtt_warning=1000
#
# Define Web (URL) monitoring list (1 < x < 255)
# web_x_url is the URL to monitor (example: http://my.site.com/folder)
# web_x_description is optional (if not set, define to URL)
# web_x_timeout is optional and overwrite the default timeout value
# web_x_rtt_warning is optional and defines the warning respond time in ms (approximately)
#
#web_1_url=https://blog.nicolargo.com
#web_1_description=My Blog
#web_1_rtt_warning=3000
#web_2_url=https://github.com
#web_3_url=http://www.google.fr
#web_3_description=Google Fr
#web_4_url=https://blog.nicolargo.com/nonexist
#web_4_description=Intranet

[docker]
disable=False
# Only show specific containers (comma separated list of container name or regular expression)
# Comment this line to display all containers (default configuration)
#show=telegraf
# Hide some containers (comma separated list of container name or regular expression)
# Comment this line to display all containers (default configuration)
#hide=telegraf
# Define the maximum docker size name (default is 20 chars)
max_name_size=20
#cpu_careful=50
# Thresholds for CPU and MEM (in %)
#cpu_warning=70
#cpu_critical=90
#mem_careful=20
#mem_warning=50
#mem_critical=70
#
# Per container thresholds
#containername_cpu_careful=10
#containername_cpu_warning=20
#containername_cpu_critical=30
#
# By default, Glances only display running containers
# Set the following key to True to display all containers
all=False

[amps]
# AMPs configuration are defined in the bottom of this file
disable=False

##############################################################################
# Client/server
##############################################################################

[serverlist]
# Define the static servers list
#server_1_name=localhost
#server_1_alias=My local PC
#server_1_port=61209
#server_2_name=localhost
#server_2_port=61235
#server_3_name=192.168.0.17
#server_3_alias=Another PC on my network
#server_3_port=61209
#server_4_name=pasbon
#server_4_port=61237

[passwords]
# Define the passwords list related to the [serverlist] section
# Syntax: host=password
# Where: host is the hostname
#        password is the clear password
# Additionally (and optionally) a default password could be defined
#localhost=abc
#default=defaultpassword
#
# Define the path of the local '.pwd' file (default is system one)
#local_password_path=~/.config/glances

##############################################################################
# Exports
##############################################################################

[graph]
# Configuration for the --export graph option
# Set the path where the graph (.svg files) will be created
# Can be overwrite by the --graph-path command line option
path=/tmp
# It is possible to generate the graphs automatically by setting the
# generate_every to a non zero value corresponding to the seconds between
# two generation. Set it to 0 to disable graph auto generation.
generate_every=60
# See following configuration keys definitions in the Pygal lib documentation
# http://pygal.org/en/stable/documentation/index.html
width=800
height=600
style=DarkStyle

[influxdb]
# !!!
# Will be DEPRECATED in future release.
# Please have a look on the new influxdb2 export module (compatible with InfluxDB 1.8.x and 2.x)
# !!!
# Configuration for the --export influxdb option
# https://influxdb.com/
host=localhost
port=8086
protocol=http
user=root
password=root
db=glances
# Prefix will be added for all measurement name
# Ex: prefix=foo
#     => foo.cpu
#     => foo.mem
# You can also use dynamic values
#prefix=foo
# Following tags will be added for all measurements
# You can also use dynamic values.
# Note: hostname is always added as a tag
#tags=foo:bar,spam:eggs,domain:`domainname`

[influxdb2]
# Configuration for the --export influxdb2 option
# https://influxdb.com/
host=localhost
port=8086
protocol=http
org=nicolargo
bucket=glances
token=EjFUTWe8U-MIseEAkaVIgVnej_TrnbdvEcRkaB1imstW7gapSqy6_6-8XD-yd51V0zUUpDy-kAdVD1purDLuxA==
# Prefix will be added for all measurement name
# Ex: prefix=foo
#     => foo.cpu
#     => foo.mem
# You can also use dynamic values
#prefix=foo
# Following tags will be added for all measurements
# You can also use dynamic values.
# Note: hostname is always added as a tag
#tags=foo:bar,spam:eggs,domain:`domainname`

[cassandra]
# Configuration for the --export cassandra option
# Also works for the ScyllaDB
# https://influxdb.com/ or http://www.scylladb.com/
host=localhost
port=9042
protocol_version=3
keyspace=glances
replication_factor=2
# If not define, table name is set to host key
table=localhost
# If not define, username and password will not be used
#username=cassandra
#password=password

[opentsdb]
# Configuration for the --export opentsdb option
# http://opentsdb.net/
host=localhost
port=4242
#prefix=glances
#tags=foo:bar,spam:eggs

[statsd]
# Configuration for the --export statsd option
# https://github.com/etsy/statsd
host=localhost
port=8125
#prefix=glances

[elasticsearch]
# Configuration for the --export elasticsearch option
# Data are available via the ES RESTful API. ex: URL/<index>/cpu
# https://www.elastic.co
scheme=http
host=localhost
port=9200
index=glances

[riemann]
# Configuration for the --export riemann option
# http://riemann.io
host=localhost
port=5555

[rabbitmq]
# Configuration for the --export rabbitmq option
#host=localhost
#port=5672
#user=guest
#password=guest
#queue=glances_queue
#protocol=amqps

[mqtt]
# Configuration for the --export mqtt option
#host=localhost
#port=8883
#tls=false
#user=guest
#password=guest
#topic=glances
#topic_structure=per-metric

[couchdb]
# Configuration for the --export couchdb option
# https://www.couchdb.org
host=localhost
port=5984
db=glances
# user and password are optional (comment if not configured on the server side)
# If they are used, then the https protocol will be used
#user=root
#password=root

[mongodb]
# Configuration for the --export mongodb option
# https://www.mongodb.com
host=localhost
port=27017
db=glances
user=root
password=example

[kafka]
# Configuration for the --export kafka option
# http://kafka.apache.org/
host=localhost
port=9092
topic=glances
#compression=gzip
# Tags will be added for all events
#tags=foo:bar,spam:eggs
# You can also use dynamic values
#tags=hostname:`hostname -f`

[zeromq]
# Configuration for the --export zeromq option
# http://www.zeromq.org
# Use * to bind on all interfaces
host=*
port=5678
# Glances envelopes the stats in a publish message with two frames:
# - First frame containing the following prefix (STRING)
# - Second frame with the Glances plugin name (STRING)
# - Third frame with the Glances plugin stats (JSON)
prefix=G

[prometheus]
# Configuration for the --export prometheus option
# https://prometheus.io
# Create a Prometheus exporter listening on localhost:9091 (default configuration)
# Metric are exporter using the following name:
#   <prefix>_<plugin>_<stats>{labelkey:labelvalue}
# Note: You should add this exporter to your Prometheus server configuration:
#   scrape_configs:
#    - job_name: 'glances_exporter'
#      scrape_interval: 5s
#      static_configs:
#        - targets: ['localhost:9091']
#
# Labels will be added for all measurements (default is src:glances)
#  labels=foo:bar,spam:eggs
# You can also use dynamic values
#  labels=system:`uname -s`
#
host=localhost
port=9091
#prefix=glances
labels=src:glances

[restful]
# Configuration for the --export restful option
# Example, export to http://localhost:6789/
host=localhost
port=6789
protocol=http
path=/

[amp_systemd]
# Use the Systemd AMP
enable=false
regex=\/lib\/systemd\/systemd
refresh=30
one_line=true
systemctl_cmd=/bin/systemctl --plain

[amp_systemv]
# Use the Systemv AMP
enable=false
regex=\/sbin\/init
refresh=30
one_line=true
service_cmd=/usr/bin/service --status-all
EOH
	destination = "local/glances.conf"
      }
    }
  }
}
