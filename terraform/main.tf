terraform {
  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.19.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket  = "pihole-tfstate"
    key     = "terraform.tfstate"
    region  = "us-east-2"
    encrypt = true
  }
}

provider "tailscale" {
  oauth_client_id     = var.ts_client_id
  oauth_client_secret = var.ts_client_secret
  tailnet             = var.ts_tail_net
}

provider "aws" {
}

resource "aws_instance" "pihole" {
  depends_on             = [tailscale_tailnet_key.ts_key]
  ami                    = "ami-02da2f5b47450f5a8"
  instance_type          = "t2.micro"
  key_name               = "aws-pihole"
  vpc_security_group_ids = [aws_security_group.pihole_sg.id]
  private_ip             = "172.31.23.23"
  subnet_id              = "subnet-09a9907e2715f5ec6"

  user_data = <<-EOF
                #!/bin/bash
                # exec > /var/log/user-data.log 2>&1
                sudo mkdir -p /etc/pihole
                hostnamectl set-hostname ${var.instance_hostname}

                sudo cat << 'EOT' > /etc/pihole/setupVars.conf
                ${file("../scripts/pihole.conf")}
                EOT

                cat << 'EOT' > ./adlist.txt
                ${file("../scripts/adlist.txt")}
                EOT

                printf "Installing Pi-hole non-interactively...\n"
                curl -sSL https://install.pi-hole.net | bash /dev/stdin --unattended
                sudo apt install sqlite3 -y

                printf "Configuring adlists...\n"
                while read -r url; do
                  sudo sqlite3 /etc/pihole/gravity.db "INSERT INTO adlist (address, enabled, comment) VALUES ('$url', 1, 'Added via script');"
                done < ./adlist.txt
                sudo pihole -g

                sudo pihole setpassword "${var.pihole_pass}"

                printf "Enabling Pi-hole to start on boot...\n"
                sudo systemctl enable pihole-FTL

                printf "Installing Tailscale...\n"
                curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
                curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
                sudo apt update && sudo apt upgrade -y
                sudo apt-get install -y tailscale

                printf "Starting Tailscale...\n"
                printf "Tailscale auth key: %s\n" "${tailscale_tailnet_key.ts_key.key}"
                sudo tailscale up --auth-key="${tailscale_tailnet_key.ts_key.key}"

                printf "Enabling Tailscale to start on boot...\n"
                sudo systemctl enable tailscaled
                EOF

  tags = {
    Name = "aws-pihole-server"
  }

  connection {
    type        = "ssh"
    user        = "admin"
    private_key = var.aws_pihole_pem
    host        = chomp(trimspace(shell("tailscale ip -4")))
  }
}
resource "aws_security_group" "pihole_sg" {
  name        = "pihole-security-group"
  description = "Outbound traffic for Pi-hole"
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
resource "tailscale_tailnet_key" "ts_key" {
  reusable            = false
  ephemeral           = true
  expiry              = 3600
  description         = "aws pihole key"
  tags                = ["tag:pihole"]
  recreate_if_invalid = "always"
}
data "tailscale_device" "pihole" {
  hostname   = var.instance_hostname
  depends_on = [aws_instance.pihole]
  wait_for   = "120s"
}
resource "tailscale_dns_nameservers" "pihole_dns" {
  nameservers = [data.tailscale_device.pihole.addresses[0]]
  depends_on  = [data.tailscale_device.pihole]
}
resource "tailscale_dns_preferences" "dns_prefs" {
  magic_dns = true
}
resource "null_resource" "override_local_dns" {
  depends_on = [aws_instance.pihole]

  provisioner "local-exec" {
    command = <<-EOT
      ACCESS_TOKEN=$(curl -s -X POST https://api.tailscale.com/api/v2/oauth/token \
          -d "client_id=${var.ts_client_id}" \
          -d "client_secret=${var.ts_client_secret}" \
          -d "grant_type=client_credentials" | jq -r '.access_token')
      curl -X POST "https://api.tailscale.com/api/v2/tailnet/${var.ts_tail_net}/dns/preferences" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"override_local_dns": true}'
    EOT
  }
}