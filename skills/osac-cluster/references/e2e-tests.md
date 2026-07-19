# Run E2E tests on a cluster

**Read this when the user wants to run OSAC E2E tests** (after refresh).

After refresh, you can run the OSAC E2E test suite against your cluster.

## Prerequisites

```bash
git clone https://github.com/osac-project/osac-test-infra.git
cd osac-test-infra
pip install -e .
```

You also need the `osac` CLI binary. Check the test-infra repo for the current required version.

## VMaaS tests

```bash
export KUBECONFIG=~/.kube/<name>.kubeconfig
export OSAC_VM_KUBECONFIG=$KUBECONFIG
export OSAC_NAMESPACE=osac-e2e-ci
export OSAC_CLI_PATH=<path-to-osac-binary>

cd osac-test-infra
make test-vmaas
```

## CaaS tests

```bash
export KUBECONFIG=~/.kube/<name>.kubeconfig
export OSAC_VM_KUBECONFIG=$KUBECONFIG
export OSAC_NAMESPACE=osac-e2e-ci
export OSAC_CLI_PATH=<path-to-osac-binary>
export OSAC_PULL_SECRET_PATH=<path-to-osac-installer>/values/caas-ci/pull-secret.json
export OSAC_SSH_PUBLIC_KEY_PATH=~/.config/cluster-tool/cluster-tool.key.pub
export OSAC_CLUSTER_TEMPLATE=osac.templates.ocp_ci_small

cd osac-test-infra
make test-caas
```

## Run a specific test

```bash
make test TEST=test_compute_instance_lifecycle
```
