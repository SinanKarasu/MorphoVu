SHELL := /bin/bash

.PHONY: bootstrap build clean

bootstrap:
	./Scripts/bootstrap-manifold.sh

build:
	swift build

clean:
	rm -rf .build vendor/manifold-lib vendor/ManifoldBinary.xcframework
