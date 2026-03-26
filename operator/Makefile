LOCALBIN ?= $(shell pwd)/bin
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen

.PHONY: manifests
manifests:
	$(CONTROLLER_GEN) rbac:roleName=manager-role crd paths="./..." output:crd:artifacts:config=config/crd/bases

.PHONY: generate
generate:
	$(CONTROLLER_GEN) object:headerFile="" paths="./..."

.PHONY: fmt
fmt:
	gofmt -w ./api ./internal ./main.go

.PHONY: vet
vet:
	go vet ./...

.PHONY: build
build:
	go build ./...
