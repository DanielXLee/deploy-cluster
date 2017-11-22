# Deploy Cluster
Deploy cluster with open source xCAT

## Create os image
Create an os image before provision node with command:
```bash
sh node-management.sh -t osimage
```

## Provisioning node
Prepare a node information file before provisioning.

Example of a node information file:

This entry defines a node.
>nodes:
&ensp;&ensp;node01:
&ensp;&ensp;&ensp;&ensp;mac=b8:ac:6f:37:59:25
&ensp;&ensp;&ensp;&ensp;nicips='eth0!10.10.10.3,eth1!20.20.20.3'
