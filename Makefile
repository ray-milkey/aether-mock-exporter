# SPDX-FileCopyrightText: 2022-present Intel Corporation
# SPDX-FileCopyrightText: 2020-present Open Networking Foundation <info@opennetworking.org>
#
# SPDX-License-Identifier: Apache-2.0

# If any command in a pipe has nonzero status, return that status
SHELL = bash -o pipefail

export CGO_ENABLED=1
export GO111MODULE=on

.PHONY: build

KIND_CLUSTER_NAME           ?= kind
DOCKER_REPOSITORY           ?= onosproject/
ONOS_SDCORE_ADAPTER_VERSION ?= latest

all: build images

images: # @HELP build simulators image
images: aether-mock-exporter-docker

deps: # @HELP ensure that the required dependencies are in place
	GOPRIVATE="github.com/onosproject/*" go build -v ./...
	bash -c "diff -u <(echo -n) <(git diff go.mod)"
	bash -c "diff -u <(echo -n) <(git diff go.sum)"

linters: golang-ci # @HELP examines Go source code and reports coding problems
	golangci-lint run --timeout 5m

build-tools: # @HELP install the ONOS build tools if needed
	@if [ ! -d "../build-tools" ]; then cd .. && git clone https://github.com/onosproject/build-tools.git; fi

jenkins-tools: # @HELP installs tooling needed for Jenkins
	cd .. && go get -u github.com/jstemmer/go-junit-report && go get github.com/t-yuki/gocover-cobertura

golang-ci: # @HELP install golang-ci if not present
	golangci-lint --version || curl -sfL https://install.goreleaser.com/github.com/golangci/golangci-lint.sh | sh -s -- -b `go env GOPATH`/bin v1.42.0

license_check: build-tools # @HELP examine and ensure license headers exist
	./../build-tools/licensing/boilerplate.py -v --rootdir=${CURDIR} --boilerplate LicenseRef-ONF-Member-1.0

# @HELP build the go binary in the cmd/aether-mock-exporter package
build:
	go build -o build/_output/aether-mock-exporter ./cmd/aether-mock-exporter

test: build deps license_check linters
	go test -cover -race github.com/onosproject/aether-mock-exporter/pkg/...
	go test -cover -race github.com/onosproject/aether-mock-exporter/cmd/...

jenkins-test:  # @HELP run the unit tests and source code validation producing a junit style report for Jenkins
jenkins-test: build deps license_check linters
	TEST_PACKAGES=github.com/onosproject/aether-mock-exporter/... ./../build-tools/build/jenkins/make-unit

coverage: # @HELP generate unit test coverage data
coverage: build deps linters license_check
	export GOPRIVATE="github.com/onosproject/*"
	go test -covermode=count -coverprofile=onos.coverprofile github.com/onosproject/aether-mock-exporter/pkg/...
	cd .. && go get github.com/mattn/goveralls && cd aether-mock-exporter
	grep -v .pb.go onos.coverprofile >onos-nogrpc.coverprofile
	goveralls -coverprofile=onos-nogrpc.coverprofile -service travis-pro -repotoken McoQ4G2hx3rgBaA45sm2aVO25hconX70N

aether-mock-exporter-docker:
	docker build . -f Dockerfile \
	-t ${DOCKER_REPOSITORY}aether-mock-exporter:${ONOS_SDCORE_ADAPTER_VERSION}

kind: # @HELP build Docker images and add them to the currently configured kind cluster
kind: images kind-only

kind-only: # @HELP deploy the image without rebuilding first
kind-only:
	@if [ "`kind get clusters`" = '' ]; then echo "no kind cluster found" && exit 1; fi
	kind load docker-image --name ${KIND_CLUSTER_NAME} ${DOCKER_REPOSITORY}aether-mock-exporter:${ONOS_SDCORE_ADAPTER_VERSION}

publish: # @HELP publish version on github and dockerhub
	./../build-tools/publish-version ${VERSION} onosproject/aether-mock-exporter

jenkins-publish: build-tools jenkins-tools # @HELP Jenkins calls this to publish artifacts
	./build/bin/push-images
	../build-tools/release-merge-commit

clean: # @HELP remove all the build artifacts
	rm -rf ./build/_output
	rm -rf ./vendor
	rm -rf ./cmd/aether-mock-exporter/aether-mock-exporter

help:
	@grep -E '^.*: *# *@HELP' $(MAKEFILE_LIST) \
    | sort \
    | awk ' \
        BEGIN {FS = ": *# *@HELP"}; \
        {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}; \
    '
