.PHONY: deploy destroy logs

deploy:
	./deploy.sh

destroy:
	./destroy.sh

logs:
	echo "Use Tailscale shell first, then run:"
	echo "sudo docker compose -p ghost -f /opt/ghost/compose.yaml --env-file /opt/ghost/ghost.env logs -f"
