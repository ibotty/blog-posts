# Configuring a Ceph Bluestore OSD on a LVM volume

This post shows how to create a OSD using a raw LVM volume, using Bluestore, Ceph's new storage format.

I assume Ceph's Luminous release (12.2).
The instructions might not work with newer releases.
They certainly won't work with older releases.

`<cluster-name>` is usually just `ceph`, `<vg>` is the volume group, `<osd-lv>` is the logical volume to use for the OSD.


## Why?

> Sometimes small, contained, non optimal performing, is just the right tool :)

-- <cite>sep on Ceph's irc channel</cite>

When running a hyperconverged infrastructure, i.e. colocating your cluster's computing and storage nodes, you might not always have a separate disk for Ceph on every node.
I like using LVM for that use case.
(Though I am looking forward to replace LVM with [Stratis](https://stratis-storage.github.io/), when it is ready)! 

Unfortunately, `ceph-disk` (and thus Ceph's deployment options `ceph-ansible` and `ceph-deploy`) don't support Bluestore on LVM (on Ceph Luminous).

## Drawbacks

Ceph does not recommend running OSDs on disks that are used for anything else. It cannot reason about the performance of the OSD's disk when other processes are using the disk.

Resizing the logical volume used for the OSD does not work.
As it is not in focus for Ceph HQ (You cannot resize physical disks!), I don't think it is going to be fixed. (TODO: file bug, and add reference here.)


## How

### Create OSD

Configure Ceph's configuration (`/etc/ceph/<cluster-name>.conf`) to use bluestore for new OSDs by adding the following configuration option to its `[global]` section. Commands below use the default cluster, if you use another cluster name, change the command accordingly.

```
[global]
osd objectstore = bluestore
```

Register the to be created OSD.

```shell
> ceph osd create
```

That will return the newly created osd number. Record that number. It will be called `N` from now on.

Add sections to `/etc/ceph/<cluster-name>.conf`.

```
[osd.<N>]
host = <node name>
osd data = /var/lib/ceph/osd/ceph-<N>/
bluestore block path = /dev/<vg>/<ceph-lv>
```

The following steps create and start the OSD.

```shell
> mkdir /var/lib/ceph/osd/ceph-<N>
> ceph-osd --mkfs --mkkey -i <N>
> ceph auth add osd.<N> osd 'allow *' mon 'allow rwx' -i /var/lib/ceph/osd/ceph-<N>/keyring
> chown -R ceph:ceph /var/lib/ceph/osd/ceph-<N>/
> chown ceph:ceph /dev/<vg>/<ceph-lv>
> systemctl start ceph-osd@<N>
```

### Persisting proper starting the OSD

I could not (with reasonable effort) get `ceph-disk trigger` start the right OSD unit, so I did the hacky `/etc/rc.local` way.

```shell
> chmod +x /etc/rc.local
> echo -e "chgrp ceph /dev/<vg>/<ceph-lv>\nsystemctl start ceph-osd@<N>" \
      >> /etc/rc.local
```
