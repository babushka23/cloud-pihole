# AWS Variables
output "instance_id" {
  description = "The ID of the EC2 instance"
  value       = aws_instance.pihole.id
}

variable "aws_pihole_pem" {
  description = "The AWS pem for ssh access"
  type        = string
  sensitive   = true
}
variable "instance_hostname" {
  description = "The hostname for the instance"
  type        = string
  default     = "aws-pihole"
}
# Pihole variables
variable "pihole_pass" {
  description = "The password for the Pi-hole admin interface"
  type        = string
  sensitive   = true

}
# Tailscale variables

variable "ts_tail_net" {
  description = "The Tailscale tailnet"
  type        = string
  default     = "tailf38a0.ts.net"
}
variable "ts_client_id" {
  description = "The Tailscale client ID"
  type        = string
  sensitive   = true
}
variable "ts_client_secret" {
  description = "The Tailscale client secret"
  type        = string
  sensitive   = true
}