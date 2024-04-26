## IP repo dir

set_property ip_repo_paths "[get_property ip_repo_paths [current_project]] $::env(BINARIES_DIR)/ip" [current_project]
update_ip_catalog

## assign_bd_address

assign_bd_address
