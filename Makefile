IMAGE ?= weak-link-ssh:latest
GHCR_OWNER = scaleoutsean
GHCR_IMAGE ?= ghcr.io/${GHCR_OWNER}/weak-link-ssh:latest

.PHONY: build tag-ghcr push-ghcr push-dockerhub publish clean

build:
	docker build -t $(IMAGE) .

tag-ghcr:
	docker tag $(IMAGE) $(GHCR_IMAGE)

push-ghcr: build
	@echo "Pushing to GHCR: $(GHCR_IMAGE)"
	@docker tag $(IMAGE) $(GHCR_IMAGE)
	@docker push $(GHCR_IMAGE)

publish: push-ghcr
	@echo "Done."

clean:
	docker rmi -f $(IMAGE) || true
