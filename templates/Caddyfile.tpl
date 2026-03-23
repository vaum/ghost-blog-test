{
{{CADDY_GLOBAL_OPTIONS}}
}

{{DOMAIN}} {
	encode gzip zstd

	@bootstrap path /__bootstrap
	handle @bootstrap {
		root * /srv/status
		rewrite * /bootstrap-status.json
		file_server
	}

	reverse_proxy ghost:2368
}
{{ADMIN_DOMAIN_BLOCK}}
