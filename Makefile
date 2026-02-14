IMAGE ?= weak-link-ssh:ubuntu16.04
GHCR_IMAGE ?= ghcr.io/${GHCR_OWNER:-your-org}/weak-link-ssh:ubuntu16.04
DOCKERHUB_IMAGE ?= ${DOCKERHUB_USER:-youruser}/weak-link-ssh:ubuntu16.04

.PHONY: build tag-ghcr push-ghcr push-dockerhub publish clean

build:
	docker build -t $(IMAGE) .

tag-ghcr:
	docker tag $(IMAGE) $(GHCR_IMAGE)

push-ghcr: build
	@echo "Pushing to GHCR: $(GHCR_IMAGE)"
	@docker tag $(IMAGE) $(GHCR_IMAGE)
	@docker push $(GHCR_IMAGE)

push-dockerhub: build
	@echo "Pushing to Docker Hub: $(DOCKERHUB_IMAGE)"
	@docker tag $(IMAGE) $(DOCKERHUB_IMAGE)
	@docker push $(DOCKERHUB_IMAGE)

publish: push-ghcr
	@echo "Done. Run 'make push-dockerhub' if you also want to push to Docker Hub."

clean:
	docker rmi -f $(IMAGE) || true
