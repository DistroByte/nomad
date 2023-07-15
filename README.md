# Nomad

This repo serves as an offsite store of my nomad job specs for both recovery and education.

## Docs

For more in-depth docs on my homelab, visit [docs.james-hackett.ie](https://docs.james-hackett.ie).

## Jobs to note

The `vms` directory contains a job spec to place a new VM on the same network as the host, as if it
were another host with a physical interface. This makes routing to it much easier, and allows address
specific tasks (like DNS) to always be bound to the same IP address.

Because nomad can schedule jobs on any available node, this means that (in theory) a VM with bind9
could always be found at the same address, regardless of the state of the hardware it is running on.

## Changelog

A changelog can be found [here](CHANGELOG.md)
