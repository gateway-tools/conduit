.PHONY: build test pkg

NODE_VERSION := 16

all: build test pkg

help:
	@echo "Builds and compiles a static binary"
	@echo "The following command are available"
	@echo "- build: runs npm install and pkg"
	@echo "- test: runs test suite"
	@echo "- pkg: packages the project into a static binary"

build:
	@npm install

test:
	( NODE_ENV="test" ASK_ENABLED="true" npm run test || exit 1)

pkg:
	@./node_modules/.bin/pkg -t node$(value NODE_VERSION)-linuxstatic-x64 index.js

image:
	@docker \
	build \
	--rm \
	conduit \
	.