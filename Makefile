.DEFAULT_GOAL := verify

CHARTS := charts/soha charts/soha-agent charts/soha-hermes-agent
PACKAGE_DIR ?= .cr-release-packages
REPO_DIR ?= .cr-index
HELM_LINT_AGENT_TOKEN ?= test-agent-token-123456
HELM_LINT_RUNNER_TOKEN ?= test-runner-token-123456

.PHONY: verify lint package repo clean

verify: lint repo ## Lint charts, package them, and verify the local repository.
	@tmp="$$(mktemp -d)"; \
	export HELM_REPOSITORY_CONFIG="$$tmp/repositories.yaml"; \
	export HELM_REPOSITORY_CACHE="$$tmp/cache"; \
	mkdir -p "$$HELM_REPOSITORY_CACHE" "$$tmp/pull"; \
	python3 -m http.server 8879 --directory "$(REPO_DIR)" >/tmp/soha-helm-http.log 2>&1 & \
	server_pid="$$!"; \
	trap 'kill "$$server_pid"; rm -rf "$$tmp"' EXIT; \
	for _ in 1 2 3 4 5; do \
		curl -fsS http://127.0.0.1:8879/index.yaml >/dev/null && break; \
		sleep 1; \
	done; \
	helm repo add opensoha http://127.0.0.1:8879 >/dev/null; \
	helm repo update >/dev/null; \
	helm pull opensoha/soha --version 0.1.0 --destination "$$tmp/pull" >/dev/null; \
	helm pull opensoha/soha-agent --version 0.1.0 --destination "$$tmp/pull" >/dev/null; \
	helm pull opensoha/soha-hermes-agent --version 0.1.0 --destination "$$tmp/pull" >/dev/null

lint: ## Lint and render all charts.
	helm lint charts/soha
	helm lint charts/soha-agent \
		--set-string secrets.agentBearerToken="$(HELM_LINT_AGENT_TOKEN)" \
		--set-string secrets.controlPlaneBearerToken="$(HELM_LINT_RUNNER_TOKEN)"
	helm lint charts/soha-hermes-agent \
		--set-string secrets.controlPlaneBearerToken="$(HELM_LINT_RUNNER_TOKEN)"
	helm template soha charts/soha >/tmp/soha-chart.yaml
	helm template soha-agent charts/soha-agent \
		--set-string secrets.agentBearerToken="$(HELM_LINT_AGENT_TOKEN)" \
		--set-string secrets.controlPlaneBearerToken="$(HELM_LINT_RUNNER_TOKEN)" \
		>/tmp/soha-agent-chart.yaml
	helm template soha-hermes-agent charts/soha-hermes-agent \
		--set-string secrets.controlPlaneBearerToken="$(HELM_LINT_RUNNER_TOKEN)" \
		>/tmp/soha-hermes-agent-chart.yaml

package: ## Package charts into $(PACKAGE_DIR).
	rm -rf "$(PACKAGE_DIR)"
	mkdir -p "$(PACKAGE_DIR)"
	@for chart in $(CHARTS); do \
		helm package "$$chart" --destination "$(PACKAGE_DIR)"; \
	done

repo: package ## Rebuild index.yaml for Artifact Hub and Helm clients.
	rm -rf "$(REPO_DIR)"
	mkdir -p "$(REPO_DIR)"
	cp "$(PACKAGE_DIR)"/*.tgz "$(REPO_DIR)"/
	helm repo index "$(REPO_DIR)"
	cp artifacthub-repo.yml "$(REPO_DIR)"/
	cp README.md "$(REPO_DIR)"/
	touch "$(REPO_DIR)/.nojekyll"

clean:
	rm -rf "$(PACKAGE_DIR)" "$(REPO_DIR)"
