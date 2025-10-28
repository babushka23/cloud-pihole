output "ts_ip" {
  description = "The Tailscale IP address of the instance"
  value       = data.tailscale_device.pihole.addresses[0]
}

output "tailscale_nameservers_preferences" {
  description = "The Tailscale DNS nameservers preferences"
  value       = resource.tailscale_dns_preferences.dns_prefs
}