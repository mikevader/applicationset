VERSION_PACKAGE=github.com/argoproj/applicationset/common
VERSION?=$(shell cat VERSION)
IMAGE_NAMESPACE?=argoproj
IMAGE_PLATFORMS?=linux/amd64,linux/arm64
IMAGE_NAME?=argocd-applicationset
IMAGE_TAG?=latest
CONTAINER_REGISTRY?=quay.io
GIT_COMMIT = $(shell git rev-parse HEAD)
LDFLAGS = -w -s -X ${VERSION_PACKAGE}.version=${VERSION} \
	-X ${VERSION_PACKAGE}.gitCommit=${GIT_COMMIT}

MKDOCS_DOCKER_IMAGE?=squidfunk/mkdocs-material:4.1.1
MKDOCS_RUN_ARGS?=

CURRENT_DIR=$(shell pwd)

KUSTOMIZE = $(shell pwd)/bin/kustomize
CONTROLLER_GEN = $(shell pwd)/bin/controller-gen

ifdef IMAGE_NAMESPACE

	ifdef CONTAINER_REGISTRY
		IMAGE_PREFIX=${CONTAINER_REGISTRY}/${IMAGE_NAMESPACE}/
	else
		IMAGE_PREFIX=${IMAGE_NAMESPACE}/
	endif

else
	IMAGE_PREFIX=
endif


# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

.PHONY: build
build: manifests fmt vet
	CGO_ENABLED=0 go build -ldflags="${LDFLAGS}" -o ./dist/argocd-applicationset .

.PHONY: test
test: generate fmt vet manifests
	echo "do tests"

.PHONY: image
image: test
	docker buildx build --platform $(IMAGE_PLATFORMS) -t ${IMAGE_PREFIX}${IMAGE_NAME}:${IMAGE_TAG} .

.PHONY: image-push
image-push: image
	docker push ${IMAGE_PREFIX}${IMAGE_NAME}:${IMAGE_TAG}

.PHONY: deploy
deploy: kustomize manifests
	${KUSTOMIZE} build manifests/namespace-install | kubectl apply -f -
	kubectl patch deployment -n argocd argocd-applicationset-controller --type='json' -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "$(IMAGE)"}]'

# Generate manifests e.g. CRD, RBAC etc.
.PHONY: manifests
manifests: kustomize generate
	$(CONTROLLER_GEN) crd:crdVersions=v1,maxDescLen=0 paths="./..." output:crd:artifacts:config=./manifests/crds/
	KUSTOMIZE=${KUSTOMIZE} CONTAINER_REGISTRY=${CONTAINER_REGISTRY} hack/generate-manifests.sh

# Run go fmt against code
.PHONY: fmt
fmt:
	go fmt ./...

# Run go vet against code
.PHONY: vet
vet:
	go vet ./...

# Generate code
generate: controller-gen
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

controller-gen: ## Download controller-gen to '(project root)/bin', if not already present.
	$(call go-get-tool,$(CONTROLLER_GEN),sigs.k8s.io/controller-tools/cmd/controller-gen@v0.3.0)


kustomize: ## Download kustomize to '(project root)/bin', if not already present.
	$(call go-get-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/v3@v3.9.4)

# go-get-tool will 'go get' any package $2 and install it to $1.
PROJECT_DIR := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))
define go-get-tool
@[ -f $(1) ] || { \
set -e ;\
TMP_DIR=$$(mktemp -d) ;\
cd $$TMP_DIR ;\
go mod init tmp ;\
echo "Downloading $(2)" ;\
GOBIN=$(PROJECT_DIR)/bin go get $(2) ;\
rm -rf $$TMP_DIR ;\
}
endef
