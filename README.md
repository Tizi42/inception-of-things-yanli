# Inception of Things (IoT)

Complete K3s, k3d, Argo CD, and local GitLab implementation for subject version 4.0. The default team login is `yanli`; set `IOT_LOGIN` before `vagrant up` or setup if a different team login must be used.

## Repository map

| Folder | Deliverable | Main proof |
|---|---|---|
| `p1` | Two Vagrant VMs, K3s server + worker | Two Ready nodes at `192.168.56.110` and `.111` |
| `p2` | One Vagrant VM, three web apps, Traefik Ingress | Host routing plus exactly three app2 replicas |
| `p3` | k3d, two namespaces, Argo CD, GitHub GitOps | A Git commit changes the live app from v1 to v2 |
| `bonus` | Latest official GitLab CE Helm chart in `gitlab` | The same GitOps update works from local GitLab |

All scripts are idempotent where the underlying installer permits it. Runtime credentials are generated locally and kept below ignored `.state` or `.vagrant` directories.

## Prerequisites

- Parts 1 and 2: Vagrant 2.4+ and VirtualBox 7+.
- Part 3: a current Ubuntu 26.04 LTS virtual machine with at least 2 CPUs and 4 GB RAM.
- Bonus: use the supplied VM defaults (6 CPUs and 12 GB RAM). GitLab's official minimum local-cluster example can barely fit in 3 CPUs and 6 GB; Argo CD and the demo workload require additional headroom.
- Internet access is required during first provisioning to download the current stable K3s, k3d, Argo CD, Kubernetes CLI, Helm, container images, and GitLab chart.

## Part 1 - K3s server and worker

```bash
cd p1
vagrant up --provider=virtualbox
vagrant ssh yanliS -c "bash /vagrant/scripts/check.sh"
```

Expected result: `yanliS` is the K3s server at `192.168.56.110`, `yanliSW` is its agent at `192.168.56.111`, both accept `vagrant ssh` without a password, and both Kubernetes nodes are Ready. The private-network interface is discovered from its IP instead of assuming `eth1` or `enp0s8`.

Notice: the `check.sh` could fail on `yanliSW` since it's the
worker. Only server can read the kuberconfig.

## Part 2 - three applications and Ingress

Destroy Part 1 first if it is still running because Part 2 uses the same private IP.

```bash
cd p1
vagrant destroy -f
cd ../p2
vagrant up --provider=virtualbox
vagrant ssh yanliS -c "bash /vagrant/scripts/check.sh"
```

Equivalent host-side checks are:

```bash
curl -H "Host: app1.com" http://192.168.56.110/
curl -H "Host: app2.com" http://192.168.56.110/
curl -H "Host: anything.invalid" http://192.168.56.110/
```

The first two requests select app1 and app2. Every unmatched host selects app3 through `spec.defaultBackend`. `kubectl -n iot-apps get ingress,deploy,pod,svc` exposes the Ingress during the defense and shows app2 at `3/3` replicas.

## Part 3 - k3d and GitHub-backed Argo CD

Publish this repository publicly on GitHub before setup. The repository name must include the team login, for example `inception-of-things-yanli`. Run these commands inside the Linux VM, not on the evaluator's host OS:

```bash
sudo bash p3/scripts/install-tools.sh
# Log out and back in once for Docker group membership.
export IOT_LOGIN=yanli
export IOT_GIT_REPO=https://github.com/Tizi42/inception-of-things.git
bash p3/scripts/setup.sh
bash p3/scripts/check.sh
```

If the public repository uses a branch other than `main`, also export `IOT_GIT_REVISION`. Setup validates that the repository is public/reachable and that its name contains the login before creating anything.

Switch version:

```bash
bash p3/scripts/switch-version.sh v2
bash p3/scripts/switch-version.sh v1
```

Each command changes `p3/confs/app/deployment.yaml`, commits and pushes it, requests an immediate Argo CD refresh, waits for sync and rollout, then curls `http://127.0.0.1:8888`. Run `bash p3/scripts/argocd-ui.sh` in another terminal to print the admin password and expose the UI at `https://127.0.0.1:8080`.

## Bonus - local GitLab-backed Argo CD

The bonus VM mounts the whole repository at `/workspace` and has enough memory for the official GitLab chart:

```bash
cd bonus
vagrant up --provider=virtualbox
vagrant reload
vagrant ssh
cd /workspace
bash bonus/scripts/setup.sh
bash bonus/scripts/check.sh
```

Setup installs the latest chart from `https://charts.gitlab.io`, creates the dedicated `gitlab` namespace, bootstraps a private local project named `inception-of-things-yanli`, stores its token only in `bonus/.state`, registers the repository with Argo CD, and deploys the same application into `dev`.

```bash
bash bonus/scripts/gitlab-credentials.sh
bash bonus/scripts/switch-version.sh v2
bash bonus/scripts/switch-version.sh v1
bash bonus/scripts/check.sh
```

The GitLab hostname uses `nip.io` and the VM private IP, so no evaluator-specific DNS server or `/etc/hosts` edit is required. Override `IOT_BONUS_IP` and `IOT_GITLAB_DOMAIN` if the private network differs.

## Useful inspection commands

```bash
kubectl get nodes -o wide
kubectl get namespaces
kubectl -n argocd get applications
kubectl -n dev get all
kubectl -n gitlab get pods
k3d cluster list
```

K3s is a lightweight Kubernetes distribution installed directly as system services. k3d is a wrapper that runs K3s nodes as Docker containers, making short-lived local clusters fast to create and replace. Argo CD continuously compares the declared Git repository state with the cluster and automatically reconciles drift through `prune` and `selfHeal`.
