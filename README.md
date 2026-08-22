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

The bonus VM mounts the whole repository at `/workspace`. Vagrant does not install any tools inside it. Install Docker, Git, Helm, jq, k3d, kubectl, curl, and OpenSSL manually for the VM user before running setup:

```bash
cd bonus
vagrant up --provider=virtualbox
vagrant ssh
cd /workspace
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

## CLI for evaluation

### Part 1 — configuration

**Host:** inspect and start the two machines.

```bash
cd p1
export IOT_LOGIN=yanli
sed -n '1,220p' Vagrantfile
vagrant validate
vagrant up --provider=virtualbox
vagrant status
```

The `Vagrantfile` shows two machines named `yanliS` and `yanliSW`, Ubuntu 26.04 for both, private addresses `192.168.56.110` and `192.168.56.111`, and separate server/worker provisioners. Confirm the guest distribution if asked:

```bash
find . -maxdepth 2 -type f | sort
sed -n '1,220p' scripts/server.sh
sed -n '1,220p' scripts/worker.sh
sed -n '1,160p' confs/server.yaml
sed -n '1,160p' confs/worker.yaml
vagrant ssh yanliS -c 'cat /etc/os-release'
vagrant ssh yanliSW -c 'cat /etc/os-release'
```

### Part 1 — SSH, interfaces, hostnames, and K3s

**Host:** prove passwordless Vagrant SSH into both machines.

```bash
vagrant ssh yanliS
vagrant ssh yanliSW
```

The same proof can be made without remaining in an interactive shell:

```bash
vagrant ssh yanliS -c 'hostname; ip -br -4 address; systemctl is-active k3s; k3s --version'
vagrant ssh yanliSW -c 'hostname; ip -br -4 address; systemctl is-active k3s-agent; k3s --version'
```

**Guest:** the exact dynamic-interface command named in the evaluation sheet is:

```bash
ip a show "$(ip route | awk '/default/ {print $5; exit}')"
```

VirtualBox retains a NAT adapter as the default route so Vagrant can SSH. Display the required static private-network address without assuming `eth1` or `enp0s8`:

```bash
ip -br -4 address
ip -o -4 address show | awk '$4 ~ /^192\.168\.56\./ {print $2, $4}'
```

Expected values:

| Machine | Hostname | Private IP | Service |
|---|---|---|---|
| Server | `yanliS` | `192.168.56.110` | `k3s` |
| Worker | `yanliSW` | `192.168.56.111` | `k3s-agent` |

**Server guest:** inspect K3s and prove that both VMs joined the same cluster.

```bash
systemctl is-active k3s
systemctl status k3s --no-pager
kubectl get nodes -o wide
bash /vagrant/scripts/check.sh
```

**Worker guest:** inspect the agent service.

```bash
systemctl is-active k3s-agent
systemctl status k3s-agent --no-pager
```

The worker intentionally has no administrator kubeconfig. Run `kubectl get nodes -o wide` on `yanliS`; both nodes must be `Ready` with internal IPs `.110` and `.111`.

### Part 2 — configuration

Stop Part 1 first because Part 2 reuses its server address.

```bash
cd p1
vagrant halt
cd ../p2
export IOT_LOGIN=yanli
sed -n '1,220p' Vagrantfile
vagrant validate
vagrant up --provider=virtualbox
vagrant status
```

The Part 2 `Vagrantfile` defines exactly one machine: `yanliS`, Ubuntu 26.04, at `192.168.56.110`.

Inspect the additional provisioning and Kubernetes files when the evaluator asks for their purpose:

```bash
find . -maxdepth 2 -type f | sort
sed -n '1,220p' scripts/server.sh
sed -n '1,220p' confs/kustomization.yaml
sed -n '1,260p' confs/applications.yaml
sed -n '1,180p' confs/ingress.yaml
```

### Part 2 — K3s, applications, and Ingress

**Guest:** enter the VM and inspect the required state.

```bash
vagrant ssh yanliS
hostname
ip a show "$(ip route | awk '/default/ {print $5; exit}')"
ip -br -4 address
systemctl is-active k3s
k3s --version
kubectl get nodes -o wide
kubectl get all -A
kubectl -n iot-apps get deployments,pods,services,ingress -o wide
```

Part 2 keeps its resources in `iot-apps`. Therefore, `kubectl -n iot-apps get all` is the namespace-specific equivalent of the sheet's `kubectl get all` command.

Prove app2 has exactly three desired and ready replicas:

```bash
kubectl -n iot-apps get deployment app2
kubectl -n iot-apps get pods -l app=app2 -o wide
kubectl -n iot-apps get deployment app2 -o jsonpath='{.spec.replicas}{" desired, "}{.status.readyReplicas}{" ready\n"}'
```

Inspect and explain the Ingress:

```bash
kubectl -n iot-apps get ingress iot-apps
kubectl -n iot-apps describe ingress iot-apps
kubectl -n iot-apps get ingress iot-apps -o yaml
```

K3s provides Traefik as the Ingress controller. My iot-apps Ingress routes requests by the HTTP Host header: app1.com goes to the app1 Service, app2.com goes to the app2 Service with three replicas, and unmatched hosts use app3 as the default backend. kubectl get all does not include Ingress, so I display it separately.

**Host or guest:** verify all three routes.

```bash
curl -fsS -H 'Host: app1.com' http://192.168.56.110/
curl -fsS -H 'Host: app2.com' http://192.168.56.110/
curl -fsS -H 'Host: anything.invalid' http://192.168.56.110/
```

```bash
vagrant ssh yanliS -c 'bash /vagrant/scripts/check.sh'
```

### Part 3 — CLI installation and configuration

Run Part 3 from the repository root in the Linux evaluation environment.

Install all required tools manually for the current user. The setup scripts never invoke a package manager or install missing dependencies. Inspect the available CLIs before setup:

```bash
docker --version
docker info
k3d version
kubectl version --client
argocd version --client
helm version
git --version
jq --version
```

Confirm the public GitHub source, team login in the repository name, and both Docker Hub tags:

```bash
git remote -v
git ls-remote https://github.com/Tizi42/inception-of-things-yanli main
grep -n 'REPO_URL\|PUSH_REPO' p3/scripts/setup.sh p3/scripts/switch-version.sh
grep -n 'image:' p3/confs/app/deployment.yaml
docker manifest inspect wil42/playground:v1 >/dev/null
docker manifest inspect wil42/playground:v2 >/dev/null
```

`setup.sh` reads from the public HTTPS repository. `switch-version.sh` pushes through `git@github.com:Tizi42/inception-of-things-yanli.git`, so the 42 VM must have an SSH key authorized for that repository. The initial defense state should declare `v1`; the evaluator then changes it to `v2`.

If earlier testing left the GitHub repository on `v2`, restore the starting state before the defense:

```bash
bash p3/scripts/switch-version.sh v1
grep -n 'image:' p3/confs/app/deployment.yaml
```

Start the infrastructure and run its automated check:

```bash
export IOT_LOGIN=yanli
bash p3/scripts/setup.sh
bash p3/scripts/check.sh
```

### Part 3 — k3d, namespaces, pods, and Argo CD

Inspect the k3d cluster and its underlying Docker containers:

```bash
k3d cluster list
k3d node list
kubectl config current-context
kubectl get nodes -o wide
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
```

Prove the required namespaces, pods, services, and Argo CD state:

```bash
kubectl get namespaces
kubectl get pods -n argocd
kubectl get pods -n dev -o wide
kubectl get all -n dev
kubectl -n argocd get applications
kubectl -n argocd get application iot-app
kubectl -n argocd get application iot-app -o jsonpath='{.spec.source.repoURL}{"\n"}{.spec.source.path}{"\n"}{.spec.destination.namespace}{"\n"}{.status.sync.status}{" / "}{.status.health.status}{"\n"}'
```

Expected application evidence:

- source repository: `https://github.com/Tizi42/inception-of-things-yanli`;
- source path: `p3/confs/app`;
- destination namespace: `dev`;
- state: `Synced / Healthy`;
- automated reconciliation: `prune: true` and `selfHeal: true`.

Inspect the complete Application manifest and reconciliation policy:

```bash
kubectl -n argocd get application iot-app -o yaml
sed -n '1,200p' p3/confs/argocd-application.yaml.tmpl
```

Prove Docker Hub is the image source and query the live application:

```bash
grep -n 'image:' p3/confs/app/deployment.yaml
kubectl -n dev get deployment playground -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
kubectl -n dev describe deployment playground | grep -F 'Image:'
curl -fsS http://127.0.0.1:8888/
printf '\n'
```

### Part 3 — Argo CD UI and CLI

Keep the following command running in one terminal:

```bash
bash p3/scripts/argocd-ui.sh
```

It prints the `admin` username and generated password, then forwards the UI to `https://127.0.0.1:8080`. Accept the local self-signed certificate in the browser. Stop the port-forward with `Ctrl-C` after the demonstration.

Optional Argo CD CLI proof from a second terminal while the port-forward is active:

```bash
ARGOCD_PASSWORD="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode)"
argocd login 127.0.0.1:8080 --username admin --password "${ARGOCD_PASSWORD}" --insecure
argocd app get iot-app
argocd app history iot-app
unset ARGOCD_PASSWORD
```

### Part 3 — GitOps v1 to v2 update

The supported defense command edits the manifest, commits and pushes it, requests an Argo CD refresh, waits for the rollout, and curls the result:

```bash
bash p3/scripts/switch-version.sh v2
bash p3/scripts/check.sh
```

To expose the Git operations individually, perform the equivalent manual workflow:

```bash
sed -i -E 's|(image: wil42/playground:)v[12]|\1v2|' p3/confs/app/deployment.yaml
git diff -- p3/confs/app/deployment.yaml
git add p3/confs/app/deployment.yaml
git commit -m 'deploy playground v2'
git push origin main
```

Request immediate repository re-evaluation and watch synchronization:

```bash
kubectl -n argocd annotate application iot-app argocd.argoproj.io/refresh=hard --overwrite
kubectl -n argocd get application iot-app -w
```

Stop the watch with `Ctrl-C` once it shows `Synced` and `Healthy`, then prove the rollout, live image, response, and Git commit:

```bash
kubectl -n dev rollout status deployment/playground --timeout=180s
kubectl -n dev get deployment playground -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
curl -fsS http://127.0.0.1:8888/
printf '\n'
git log -1 --oneline
```

If automatic synchronization did not occur, use the Argo CD UI's **Sync** button or, after `argocd login`:

```bash
argocd app sync iot-app
argocd app wait iot-app --sync --health --timeout 180
```

Switch back when another demonstration is needed:

```bash
bash p3/scripts/switch-version.sh v1
```

### Bonus — start the low-memory VM

The bonus is evaluated only if every mandatory part passes. Run the Vagrant commands on the host:

```bash
cd bonus
export IOT_LOGIN=yanli
sed -n '1,220p' Vagrantfile
vagrant validate
vagrant up --provider=virtualbox
vagrant status
vagrant ssh yanliB
```

Run the remaining commands inside `yanliB`:

```bash
cd /workspace
nproc
free -h
df -h /
bash bonus/scripts/setup.sh
bash bonus/scripts/check.sh
```

The first GitLab boot can take 20–30 minutes. Success is the final `Bonus ready` line. Temporary HTTP 503 responses during initialization are expected.

The VM defaults are designed for a resource-constrained evaluation host:

- configurable VM RAM and disk, with no automatic swap or package installation;
- 6 virtual CPUs with I/O APIC enabled so all CPUs are visible;
- sparse 50 GB virtual disk;
- one GitLab webservice and one Sidekiq replica;
- Sidekiq concurrency limited to 10;
- unnecessary KAS, registry, Prometheus, Runner, cert-manager, and bundled NGINX Ingress disabled.

### Bonus — GitLab, Helm, Kubernetes, and Argo CD

List the submitted bonus files without exposing ignored runtime credentials:

```bash
find bonus -maxdepth 3 -type f ! -path 'bonus/.state/*' | sort
```

Inspect the official GitLab chart and its Kubernetes resources:

```bash
helm list -n gitlab
helm status gitlab -n gitlab
helm get values gitlab -n gitlab
kubectl get namespaces argocd dev gitlab
kubectl get pods -n gitlab
kubectl get ingress,service -n gitlab
kubectl get pods -n argocd
kubectl get all -n dev
k3d cluster list
```

Check readiness and retrieve credentials for the GitLab UI:

```bash
bash bonus/scripts/gitlab-credentials.sh
curl -fsS http://gitlab.192.168.56.120.nip.io/-/readiness
```

The credentials script prints the local URL, the `root` username, and the generated root password. Do not commit or paste that password into documentation.

Prove Argo CD reads from the local private GitLab repository instead of GitHub:

```bash
kubectl -n argocd get application iot-app-gitlab
kubectl -n argocd get application iot-app-gitlab -o jsonpath='{.spec.source.repoURL}{"\n"}{.spec.source.path}{"\n"}{.spec.destination.namespace}{"\n"}{.status.sync.status}{" / "}{.status.health.status}{"\n"}'
kubectl -n argocd get secret gitlab-iot-repo -o jsonpath='{.data.url}' | base64 --decode
printf '\n'
```

Expected source repository: `http://gitlab.192.168.56.120.nip.io/root/inception-of-things-yanli.git`. The application must be `Synced / Healthy` and deploy into `dev`.

### Bonus — create a new repository and push code

The evaluation sheet explicitly asks for a newly created GitLab repository and a successful code push. The simplest demonstration is to use the GitLab UI to create a blank project, then run ordinary `git clone`, `git add`, `git commit`, and `git push` commands.

The following alternative performs the entire proof with the GitLab API and Git CLI. Run it inside `yanliB` from `/workspace`. It reads the ignored bootstrap token but never prints it; do not enable shell tracing:

```bash
source bonus/.state/runtime.env
eval_project="evaluation-$(date +%s)"
eval_project_json="$(curl -fsS --request POST \
  --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  --data-urlencode "name=${eval_project}" \
  --data-urlencode "path=${eval_project}" \
  --data 'visibility=private' \
  --data 'initialize_with_readme=false' \
  "http://gitlab.${GITLAB_DOMAIN}/api/v4/projects")"
eval_repo="$(jq -r '.http_url_to_repo' <<<"${eval_project_json}")"
eval_project_id="$(jq -r '.id' <<<"${eval_project_json}")"
eval_dir="$(mktemp -d)"
git -C "${eval_dir}" init -b main
printf '# GitLab evaluation repository\n' > "${eval_dir}/README.md"
git -C "${eval_dir}" add README.md
git -C "${eval_dir}" -c user.name='IoT Evaluation' -c user.email='iot-eval@localhost' commit -m 'add evaluation code'
git -C "${eval_dir}" remote add origin "${eval_repo}"
auth_header="Authorization: Basic $(printf 'root:%s' "${GITLAB_TOKEN}" | base64 -w0)"
git -C "${eval_dir}" -c "http.extraHeader=${auth_header}" push -u origin main
curl -fsS --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
  "http://gitlab.${GITLAB_DOMAIN}/api/v4/projects/${eval_project_id}/repository/tree" | jq -r '.[].name'
unset auth_header GITLAB_TOKEN
```

The final command must print `README.md`. The new project also remains visible in the GitLab UI.

### Bonus — local-GitLab GitOps v1 to v2

```bash
bash bonus/scripts/switch-version.sh v2
kubectl -n argocd get application iot-app-gitlab
kubectl -n dev get deployment playground -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
curl -fsS http://127.0.0.1:8888/
printf '\n'
bash bonus/scripts/check.sh
```

The switch script updates `deployment.yaml` through the local GitLab API, forces an Argo CD refresh, waits for `wil42/playground:v2`, and verifies the response. Prove both tags by switching back:

```bash
bash bonus/scripts/switch-version.sh v1
bash bonus/scripts/check.sh
```

### Expected error handling

The evaluation sheet requires the bonus to handle unexpected or incorrect usage. All scripts use strict shell options, validate required tools and generated state, and return a non-zero status on invalid input. These safe negative tests must fail with a clear message and must not change the declared version:

```bash
bash p3/scripts/switch-version.sh v3
bash bonus/scripts/switch-version.sh latest
```

Expected messages are `Version must be v1 or v2.`. In a clean clone where bonus setup has not completed, the following commands fail explicitly and instruct the user to finish `setup.sh`:

```bash
bash bonus/scripts/check.sh
bash bonus/scripts/gitlab-credentials.sh
```

Confirm that generated state and VM metadata cannot be committed accidentally:

```bash
git check-ignore -v bonus/.state/runtime.env
git check-ignore -v bonus/.vagrant
```

## Troubleshooting CLI reference

Use these commands when a normal check fails or when the evaluator asks how a failure would be diagnosed.

### Vagrant and VirtualBox

```bash
vagrant status
vagrant ssh-config
vagrant global-status
VBoxManage list runningvms
```

### K3s services

```bash
systemctl status k3s --no-pager
journalctl -u k3s -n 100 --no-pager
systemctl status k3s-agent --no-pager
journalctl -u k3s-agent -n 100 --no-pager
```

### Kubernetes

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get events -A --sort-by=.lastTimestamp
kubectl describe pod -n dev -l app=playground
kubectl logs -n dev deployment/playground --tail=100
kubectl rollout status -n dev deployment/playground --timeout=180s
```

For a specific failing pod:

```bash
kubectl describe pod -n NAMESPACE POD_NAME
kubectl logs -n NAMESPACE POD_NAME --all-containers --tail=100
kubectl logs -n NAMESPACE POD_NAME --all-containers --previous --tail=100
```

### k3d, Docker, and resources

```bash
k3d cluster list
k3d node list
docker ps -a
docker stats --no-stream
docker system df
free -h
swapon --show
df -h /
```

### Argo CD

```bash
kubectl -n argocd get applications
kubectl -n argocd describe application iot-app
kubectl -n argocd describe application iot-app-gitlab
kubectl -n argocd logs deployment/argocd-repo-server --tail=100
kubectl -n argocd logs statefulset/argocd-application-controller --tail=100
```

### GitLab bonus

```bash
helm status gitlab -n gitlab
kubectl get pods -n gitlab -o wide
kubectl get events -n gitlab --sort-by=.lastTimestamp
kubectl logs -n gitlab deployment/gitlab-webservice-default --all-containers --tail=100
curl -v http://gitlab.192.168.56.120.nip.io/-/readiness
```

## Cleanup and linked clones

Stop a part when moving to the next one to release RAM:

```bash
vagrant halt
```

Destroy only the VMs belonging to the current Vagrant directory after the evaluation:

```bash
vagrant destroy -f
```

`vagrant destroy` irreversibly removes that VM's local state. For the bonus, this includes the GitLab database, repositories, and Kubernetes cluster.

With `linked_clone = true`, VirtualBox/Vagrant may retain one prepared master VM after a clone is destroyed. This is normal: the master is a reusable read-only base that makes later `vagrant up` operations much faster. It is not an additional project node. Do not manually remove it while dependent clones exist.
