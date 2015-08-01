# Securing a flannel vxlan network using IPsec

TLDR:

![One does not simply setup IPsec tunnel mode](./One-does-not-simply.jpg?raw=true)

It's all about fixing the firewall.

This guide was written/tested on [atomic hosts](https://projectatomic.io) running fedora-atomic using the [Libreswan](https://libreswan.org) IPsec implementation, but it should work with only minor adaptions on other OSes and other \*swan IPsec implementations. It only uses IPv4, expanding the config to IPv6 is left as an exercise for the reader.


## Libreswan config
The gist is the following basic site-to-site config (in /etc/ipsec.d/hostA-hostB.conf) for hostA with IP 192.168.0.1 and hostB with IP 192.168.0.2, using flannel supplied net 172.16.1.0/24 and 172.16.2.0/24 respectively.

You can find the flannel config in `/run/flannel/subnet.env`.

```
conn hostA-hostB-subnet
  also=hostA-hostB
  leftsubnet=172.16.1.0/24
  rightsubnet=172.16.2.0/24

conn hostA-hostB
  type=tunnel
  leftid=@hostA.example.com
  left=192.168.0.1
  leftrsasigkey=[...]
  rightid=@hostB.example.com
  right=192.168.0.2
  rightrsasigkey=[...]
  authby=rsasig
  auto=start
```

Create a `hostX-hostY` config for every combination of X and Y with X != Y.

Consult e.g. the [The RedHat Security Guide](https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/Security_Guide/sec-Securing_Virtual_Private_Networks.html) on how to generate the keys.

See below for how to run Libreswan on atomic hosts.


## Firewall config

Firewall (iptables) rules when doing IPsec split into two parts. One with `-m policy --pol none` for the "regular" traffic and one part with `-m policy --pol ipsec` for the ipsec traffic. You most likely don't want to modify/nat/masquerade IPsec traffic, so that has to be reflected in your firewall config.

Iptables' policy module (iptables-extensions(8)) can be used to classify IPsec encrypted traffic. E.g. using

    -A INPUT -m policy --pol ipsec --dir in -j IPSEC_SECURED

iptables will only jump to the `IPSEC_SECURED` chain when the traffic has been encrypted.

Similarly, a `-m policy --pol ipsec --dir out` rule in `OUTPUT` will only apply to outgoing encrypted traffic.

VXlan uses udp port 8472 (only allow via IPsec!), IPsec uses udp port 500 and ah and esp packets. E.g.:

    -A vxlan_allow -p udp -m udp --dport 8472 -j ACCEPT
    -A ipsec_allow -p udp -m udp --dport 500 -j ACCEPT
    -A ipsec_allow -p ah -j ACCEPT
    -A ipsec_allow -p esp -j ACCEPT


### Docker and its iptables rules

Docker as of version 1.7 will insert the following rule in the `nat` table.

    -A POSTROUTING -s 172.16.1.0/24 ! -o docker0 -j MASQUERADE

Instead it should needs to be

    -A POSTROUTING -m policy --dir out --pol none -s 172.16.1.0/24 ! -o docker0 -j MASQUERADE


Using a `systemd.service(5)` `ExecStartPost` hook (in `/etc/systemd/system/docker.service.d/10-fixup-ipsec.conf`)

```
[Service]
ExecStartPost=/usr/local/sbin/fixup-docker-ipsec.sh
```

and the following script (`/usr/local/sbin/fixup-docker-ipsec.sh`) It will be fixed up automatically on docker (re)start.

```shell
#!/bin/sh
set -e
. /run/flannel/subnet.env
iptables -t nat -D POSTROUTING -s $FLANNEL_SUBNET ! -o docker0 -j MASQUERADE
iptables -t nat -I POSTROUTING -m policy --dir out --pol none -s $FLANNEL_SUBNET ! -o docker0 -j MASQUERADE
```

See [docker issue 430](https://github.com/docker/libnetwork/issues/430) if/when it is/has been fixed.


## Appendix: Automating IPsec config

It should be reasonably easy to monitor flannel's etcd config (`etcdctl exec-watch --recursive $FLANNEL_ETCD_KEY`) and generate a IPsec config like the one above. That will work better with a CA infrastructure because there won't be a need to get the public keys from somewhere though.

Contact me if you are interested in a more robust solution.

For my part, I provision atomic hosts using ansible and simply copy every config to every host.


## Appendix: Libreswan on atomic hosts.

The very simple privileged container [ibotty/ipsec-libreswan](https://github.com/docker/libnetwork/issues/430) will provide a docker container that can run IPsec.

Unfortunately, docker has to be set up after flannel, which in turn needs etcd. If you require etcd traffic to be secured by IPsec, you will need either early-docker (as on coreos) or an even grosser hack until `runC` or `rkt` are ready and integrated in atomic.

Note, that step is done automatically by `atomic install ibotty/ipsec-libreswan`.

Unpack the container into `/var/lib/machine/ipsec-libreswan` and use `systemd-nspawn` to manage the container. See [ibotty/ipsec-libreswan's install script](https://github.com/ibotty/atomic-ipsec-libreswan/blob/master/install.sh) for details.


## Dedication

Thank you guys and gals at `#swan` on freenode for the hint to look into
`MASQUERADE` rules.


