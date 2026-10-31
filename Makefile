.DEFAULT_GOAL := verify

LOCAL_VERIFY :=
ifneq ($(GITHUB_ACTIONS),true)
ifneq ($(shell command -v opensoha-verify 2>/dev/null)$(OPENSOHA_LOCAL_VERIFY_REQUIRED),)
LOCAL_VERIFY := opensoha-verify run --
endif
endif

CHARTS := charts/soha charts/soha-agent charts/soha-hermes-agent charts/soha-observability charts/soha-operator
PACKAGE_DIR ?= .cr-release-packages
REPO_DIR ?= .cr-index
HELM_LINT_AGENT_TOKEN ?= test-agent-token-123456789012345
HELM_LINT_RUNNER_TOKEN ?= test-runner-token-12345678901234

.PHONY: verify verify-run workflow-test lint render-test package repo clean

verify: ## Verify with disposable local packages; CI retains release packages.
ifeq ($(LOCAL_VERIFY),)
	$(MAKE) verify-run
else
	$(LOCAL_VERIFY) sh -c '$(MAKE) verify-run PACKAGE_DIR="$$OPENSOHA_VERIFY_DIR/packages" REPO_DIR="$$OPENSOHA_VERIFY_DIR/repo"'
endif

verify-run: workflow-test lint render-test repo
	python3 scripts/test-repository.py --repository "$(REPO_DIR)" --charts $(notdir $(CHARTS))

workflow-test: ## Require explicit publication from main; pushes only verify.
	$(LOCAL_VERIFY) python3 scripts/check-release-policy.py
	$(LOCAL_VERIFY) python3 -m unittest discover -s scripts -p 'test_release_policy.py'

lint: ## Lint and render all charts.
	$(LOCAL_VERIFY) helm lint charts/soha
	$(LOCAL_VERIFY) helm lint charts/soha-agent \
		--set-string secrets.agentBearerToken="$(HELM_LINT_AGENT_TOKEN)" \
		--set-string secrets.controlPlaneBearerToken="$(HELM_LINT_RUNNER_TOKEN)"
	$(LOCAL_VERIFY) helm lint charts/soha-hermes-agent \
		--set-string secrets.controlPlaneBearerToken="$(HELM_LINT_RUNNER_TOKEN)"
	$(LOCAL_VERIFY) helm lint charts/soha-observability
	$(LOCAL_VERIFY) helm lint charts/soha-operator
	$(LOCAL_VERIFY) helm template soha charts/soha >/dev/null
	$(LOCAL_VERIFY) helm template soha-agent charts/soha-agent \
		--set-string secrets.agentBearerToken="$(HELM_LINT_AGENT_TOKEN)" \
		--set-string secrets.controlPlaneBearerToken="$(HELM_LINT_RUNNER_TOKEN)" \
		>/dev/null
	$(LOCAL_VERIFY) helm template soha-hermes-agent charts/soha-hermes-agent \
		--set-string secrets.controlPlaneBearerToken="$(HELM_LINT_RUNNER_TOKEN)" \
		>/dev/null
	$(LOCAL_VERIFY) helm template soha-observability charts/soha-observability >/dev/null
	$(LOCAL_VERIFY) helm template soha-operator charts/soha-operator >/dev/null

render-test: ## Assert control-plane configuration rollout rendering behavior.
	$(LOCAL_VERIFY) ./scripts/test-render.sh

package: ## Package charts into $(PACKAGE_DIR).
	rm -rf "$(PACKAGE_DIR)"
	mkdir -p "$(PACKAGE_DIR)"
	@for chart in $(CHARTS); do \
		$(LOCAL_VERIFY) helm package "$$chart" --destination "$(PACKAGE_DIR)" || exit $$?; \
	done

repo: package ## Rebuild index.yaml for Artifact Hub and Helm clients.
	rm -rf "$(REPO_DIR)"
	mkdir -p "$(REPO_DIR)"
	cp "$(PACKAGE_DIR)"/*.tgz "$(REPO_DIR)"/
	$(LOCAL_VERIFY) helm repo index "$(REPO_DIR)"
	cp artifacthub-repo.yml "$(REPO_DIR)"/
	cp index.html "$(REPO_DIR)"/
	cp logo.svg "$(REPO_DIR)"/
	cp README.md "$(REPO_DIR)"/
	touch "$(REPO_DIR)/.nojekyll"

clean:
	rm -rf "$(PACKAGE_DIR)" "$(REPO_DIR)"
