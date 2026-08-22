# Inception of Things (IoT)

Complete K3s, k3d, Argo CD, and local GitLab implementation for subject version 4.0. The default team login is `yanli`; set `IOT_LOGIN` before `vagrant up` or setup if a different team login must be used.

## Definition

- Vagrant: a tool for reproducibly creating and configuring virtual machines from a `Vagrantfile`. The user describes the VM image, CPU/RAM, networking and provisioning; Vagrant then talks to a provider such as `VirtualBox` to create the VM and run the setup commands. In this project, it is used to create the machines on which `K3s` runs.

- K3s: a lightweight Kubernetes distribution. It provides the Kubernetes control plane, scheduling, networking, container runtime integration, etc., but packages them in a smaller and easier-to-deploy form than a conventional Kubernetes installation. A `K3s` server manages the cluster; agent nodes register with it and run workloads. In this  project it requires using one controller and one agent in Part 1.

- K3d: a tool that runs `K3s` clusters inside Docker containers instead of full virtual machines. It creates Docker containers representing K3s server/agent nodes, connects them with Docker networking, and gives you a usable Kubernetes cluster very quickly. `K3s` is the Kubernetes distribution; `K3d` is a convenient way to run K3s using Docker. In this project it notes that K3d requires Docker.

- Argo CD: a GitOps continuous-delivery tool for Kubernetes. The user stores the desired Kubernetes configuration in Git; `Argo CD` watches that repository, compares it with the actual cluster state, and synchronizes the cluster when they differ. In this project, changing the application version in Git causes `Argo CD` to update the application in the `dev` namespace.
- CI: Continuous Integration, a development practice where developers merge changes frequently and automatically verify them, typically by building the software and running tests on every push or pull request. A typical flow is `git push → CI system detects change → build → tests → success/failure`. Strictly speaking, `Argo CD` is mainly CD/GitOps, not CI: CI produces and validates the software/image; `Argo CD` takes the desired deployment state from Git and applies it to Kubernetes. Your subject calls the `Argo CD` exercise “continuous integration,” but technically it is much closer to continuous delivery/deployment.

## Workflow

- Vagrant → creates VMs → K3s runs Kubernetes inside them

- Docker → K3d creates K3s cluster → Argo CD watches Git → Kubernetes deployment gets updated.

## Preparation

**Redirect the download folder to somewhere else, like usb or goinfre**

```bash
export IOT_STORAGE="/path/to/large-disk/$USER/iot"
mkdir -p "$IOT_STORAGE/vagrant-home" \
         "$IOT_STORAGE/tmp" \
         "$IOT_STORAGE/virtualbox-vms"

export VAGRANT_HOME="$IOT_STORAGE/vagrant-home"
export TMPDIR="$IOT_STORAGE/tmp"
VBoxManage setproperty machinefolder "$IOT_STORAGE/virtualbox-vms"
```

## Part 1 - K3s server and worker

```bash
cd p1
vagrant up --provider=virtualbox
vagrant ssh yanliS -c "bash /vagrant/scripts/check.sh"
```

Expected result: `yanliS` is the K3s server at `192.168.56.110`, `yanliSW` is its agent at `192.168.56.111`, both accept `vagrant ssh` without a password, and both Kubernetes nodes are Ready. The private-network interface is discovered from its IP instead of assuming `eth1` or `enp0s8`.

Notice: run `check.sh` on `yanliS`, not `yanliSW`. Only the server is given the administrator kubeconfig.

## Part 2 - three applications and Ingress

Stop Part 1 first if it is still running because Part 2 uses the same private IP.

```bash
cd p1
vagrant halt
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

Publish this repository publicly on GitHub before setup. The repository name must include the team login, for example `inception-of-things-yanli`. The current scripts use `https://github.com/Tizi42/inception-of-things-yanli`, branch `main`, and an SSH push remote.

Install Docker, Git, k3d, kubectl, and curl manually for the current user before setup. The project never installs host tools or invokes privileged commands. Every entry-point script checks its own dependencies and reports missing commands before changing cluster state.

Run from the repository root:

```bash
export IOT_LOGIN=yanli
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

The bonus VM mounts the whole repository at `/workspace`. Vagrant does not install any tools automatically. Run the VM-only installer explicitly; it uses `sudo` to install Docker, Git, Helm, jq, k3d, kubectl, curl, OpenSSL, and their supporting packages:

```bash
cd bonus
vagrant up --provider=virtualbox
vagrant ssh
cd /workspace
bash bonus/scripts/install-tools.sh
# Run this only if the installer says the Docker group is not active yet:
newgrp docker
bash bonus/scripts/setup.sh
bash bonus/scripts/check.sh
```

Setup installs the official GitLab chart `9.11.12` (the newest all-in-one GitLab 18.11 chart) from `https://charts.gitlab.io`, creates the dedicated `gitlab` namespace, bootstraps a private local project named `inception-of-things-yanli`, stores its token only in `bonus/.state`, registers the repository with Argo CD, and deploys the same application into `dev`. Override `IOT_GITLAB_CHART_VERSION` only when supplying the external PostgreSQL, Redis, and object storage required by GitLab chart 10 and later.

```bash
bash bonus/scripts/gitlab-credentials.sh
bash bonus/scripts/switch-version.sh v2
bash bonus/scripts/switch-version.sh v1
bash bonus/scripts/check.sh
```

The GitLab hostname uses `nip.io` and the VM private IP, so no evaluator-specific DNS server or `/etc/hosts` edit is required. Override `IOT_BONUS_IP` and `IOT_GITLAB_DOMAIN` if the private network differs.
