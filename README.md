# tech-test

My code for the IOHK Technical Test

## Running

The easiest way to run the program is to run `./run-nodes k l`, for your values
of `k` and `l`. This calls the `run-nodes` script, which will build the program
with `nix` (so you should have `nix` installed) and run 5 slave nodes and a
master node. You can patch in more slave nodes and modify the seed here.

## NixOps

*This is not currently working. See #1.*

I have included a NixOps deployment that will provision a number of servers with
the program. The nodes configured as slaves will run a systemd service, which
starts the program with their internal AWS IP address and will restart
automatically. It would then be as simple as running

```
nixops ssh master-node
master-node> tech-test IP_ADDRESS 8080 master
```

To get this running you would need to add an AWS access key to `nixops/aws/.envrc`
and then run

```
nixops create <logical.nix> <aws.nix> -d aws
nixops deploy -d aws
```

inside the `nixops/aws` folder.

To add a new slave node, for example `node3`, you should add, `node3 = node false;`
to `nixops/logical.nix` and `node3 = node;` to `nixops/aws/aws.nix`, and then run
`nixops deploy -d aws` again.

This deployment uses `direnv` to set environment variables in directories, which
allows us to add nix files to the nix path, set AWS keys, and force nix to use a
specific state file for the nixops deployment.
