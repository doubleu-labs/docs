
ifeq ($(shell command -v podman 2> /dev/null),)
    CMD=docker
else
    CMD=podman
endif

PWD=$(shell pwd)
PORT=8000
IMAGE_NAME=labs.doubleu.codes/docs
IMAGE_TAG=dev

launch: build
	$(CMD) run --rm -it -v $(PWD):/docs -p $(PORT):$(PORT) $(IMAGE_NAME):$(IMAGE_TAG)

build:
	$(CMD) build --pull=always -t $(IMAGE_NAME):$(IMAGE_TAG) --no-cache -f Containerfile $(PWD)
