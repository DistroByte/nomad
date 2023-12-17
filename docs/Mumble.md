---
tags:
  - services
---
Mumble is an open source voice over IP tool that allows for many users to all join one voice call. It also has rudimentary text channels. See [Mumble Wiki](https://wiki.mumble.info/wiki/Main_Page) for more information.

Mumble is deployed with the [mumble](../jobs/mumble.hcl) job, and has a router defined in [traefik](../jobs/traefik.hcl) to ensure it can serve voice traffic.

The super user password is printed out to `stderr` on start unless configured otherwise. To log in as that user, set your username and add your password as shown.

![](attachments/Pasted%20image%2020231217012152.png)
