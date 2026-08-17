.DEFAULT_GOAL := verify

CHARTS := charts/soha charts/soha-agent charts/soha-hermes-agent charts/soha-observability charts/soha-operator
PACKAGE_DIR ?= .cr-release-packages
REPO_DIR ?= .cr-index
HELM_LINT_AGENT_TOKEN ?= test-agent-token-123456789012345
HELM_LINT_RUNNER_TOKEN ?= test-runner-token-12345678901234

.PHONY: verify lint render-test package repo clean

verify: lint render-test repo ## Lint charts, test rendering, package them, and verify the local repository.
	@set -eu; \
	tmp="$$(mktemp -d)"; \
	export HELM_REPOSITORY_CONFIG="$$tmp/repositories.yaml"; \
	export HELM_REPOSITORY_CACHE="$$tmp/cache"; \
	mkdir -p "$$HELM_REPOSITORY_CACHE" "$$tmp/pull"; \
	python3 -m http.server 8879 --directory "$(REPO_DIR)" >/tmp/soha-helm-http.log 2>&1 & \
	server_pid="$$!"; \
	trap 'kill "$$server_pid" 2>/dev/null || true; rm -rf "$$tmp"' EXIT; \
	for _ in 1 2 3 4 5; do \
		curl -fsS http://127.0.0.1:8879/ >/dev/null && \
			curl -fsS http://127.0.0.1:8879/index.yaml >/dev/null && break; \
		sleep 1; \
	done; \
	helm repo add opensoha http://127.0.0.1:8879 >/dev/null; \
	helm repo update >/dev/null; \
	helm pull opensoha/soha --destination "$$tmp/pull" >/dev/null; \
	helm pull opensoha/soha-agent --destination "$$tmp/pull" >/dev/null; \
	helm pull opensoha/soha-hermes-agent --destination "$$tmp/pull" >/dev/null; \
	helm pull opensoha/soha-observability --destination "$$tmp/pull" >/dev/null; \
	helm pull opensoha/soha-operator --destination "$$tmp/pull" >/dev/null

lint: ## Lint and render all charts.
	helm lint charts/soha
	helm lint charts/soha-agent \
		--set-string secrets.agentBearerToken="$(HELM_LINT_AGENT_TOKEN)" \
		--set-string secrets.controlPlaneBearerToken="$(HELM_LINT_RUNNER_TOKEN)"
	helm lint charts/soha-hermes-agent \
		--set-string secrets.controlPlaneBearerToken="$(HELM_LINT_RUNNER_TOKEN)"
	helm lint charts/soha-observability
	helm lint charts/soha-operator
	helm template soha charts/soha >/tmp/soha-chart.yaml
	helm template soha-agent charts/soha-agent \
		--set-string secrets.agentBearerToken="$(HELM_LINT_AGENT_TOKEN)" \
		--set-string secrets.controlPlaneBearerToken="$(HELM_LINT_RUNNER_TOKEN)" \
		>/tmp/soha-agent-chart.yaml
	helm template soha-hermes-agent charts/soha-hermes-agent \
		--set-string secrets.controlPlaneBearerToken="$(HELM_LINT_RUNNER_TOKEN)" \
		>/tmp/soha-hermes-agent-chart.yaml
	helm template soha-observability charts/soha-observability >/tmp/soha-observability-chart.yaml
	helm template soha-operator charts/soha-operator >/tmp/soha-operator-chart.yaml

render-test: ## Assert control-plane configuration rollout rendering behavior.
	./scripts/test-render.sh

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
	cp index.html "$(REPO_DIR)"/
	cp logo.svg "$(REPO_DIR)"/
	cp README.md "$(REPO_DIR)"/
	touch "$(REPO_DIR)/.nojekyll"

clean:
	rm -rf "$(PACKAGE_DIR)" "$(REPO_DIR)"
