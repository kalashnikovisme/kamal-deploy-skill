# Terraform Infrastructure Recipe

This recipe provisions the infrastructure Kamal needs to deploy to. It is invoked from SKILL.md Step 3a when the user does not yet have a server, a configured DNS record, or both.

After this recipe completes, **return to SKILL.md Step 3b** with a server IP and domain in hand.

---

## Scenario Detection

Ask these two questions **separately**, one at a time.

**Q1 — Hosting**

> "Do you already have a server with SSH access (you have the IP address and can SSH in)?"

- **Yes** → Note the server IP. Skip all server provisioning.
- **No** → Server must be provisioned. Continue to provider questions.

**Q2 — DNS**

> "Do you already have a DNS provider configured for your domain (the domain is registered and you can manage its DNS records)?"

- **Yes** → Note the domain name. Skip all DNS provisioning.
- **No** → DNS must be provisioned. Continue to provider questions.

---

## Scenario Matrix

| Has server? | Has DNS? | What to do |
|---|---|---|
| Yes | Yes | No Terraform needed. Collect IP + domain, return to SKILL.md Step 3b. |
| Yes | No | **DNS-only**: provision only the A record pointing to the existing server. |
| No | Yes | **Server-only**: provision only the server and firewall; user adds the A record manually after. |
| No | No | **Full**: provision server, firewall, and DNS A record. |

---

## Derive app_name

Before asking any questions, derive `app_name` from the project:

1. Take the base name of the current working directory.
2. Lowercase it.
3. Replace any character that is not alphanumeric or a hyphen with a hyphen.
4. Trim leading/trailing hyphens.

Example: directory `My App` → `my-app`, `example.com` → `example-com`.

Write `app_name = "<derived-value>"` directly into `terraform/terraform.tfvars` when creating that file. Do **not** include it in `terraform.tfvars.example` — it is never something the user needs to fill in.

---

## Provider Questions

Ask only what is relevant to the scenario.

**If server needs to be provisioned — ask hosting provider:**

> "Which hosting provider do you want to use?"

Options:
- DigitalOcean
- Hetzner Cloud
- AWS (EC2)
- Other (ask for provider name; generate best-effort config with a note to verify against the Terraform Registry)

Then ask only the follow-up questions for the chosen provider:

**If DigitalOcean:**
- Region — options: `nyc3`, `ams3`, `fra1`, `sgp1`, `lon1`, `syd1`
- Droplet size — options: `s-1vcpu-1gb` (1 GB), `s-1vcpu-2gb` (2 GB), `s-2vcpu-4gb` (4 GB)
- SSH key — ask:

  > "Do you have an SSH key already uploaded to your DigitalOcean account, or do you want to upload a new one?"

  - **Existing key in DigitalOcean** → ask for the key name exactly as it appears in DigitalOcean → API → SSH Keys (or Settings → Security → SSH Keys). Use the `data "digitalocean_ssh_key"` data source.
  - **New key (upload from local file)** → ask for the path to the public key file (default: `~/.ssh/id_ed25519.pub`). Use the `digitalocean_ssh_key` resource.

**If Hetzner Cloud:**
- Location — options: `nbg1` (Nuremberg), `fsn1` (Falkenstein), `hel1` (Helsinki), `ash` (Ashburn), `hil` (Hillsboro)
- Server type — options: `cx22` (2 vCPU 4 GB), `cx32` (4 vCPU 8 GB), `cax11` (ARM 2 vCPU 4 GB)
- SSH public key path (default: `~/.ssh/id_ed25519.pub`)

**If AWS (EC2):**
- Region — options: `us-east-1`, `us-west-2`, `eu-west-1`, `eu-central-1`, `ap-southeast-1`
- Instance type — options: `t3.micro` (1 GB), `t3.small` (2 GB), `t3.medium` (4 GB)
- SSH public key path (default: `~/.ssh/id_ed25519.pub`)

**If Other:**
- Ask for the provider name and generate best-effort config with a note to verify against the Terraform Registry.

**If DNS needs to be provisioned — ask DNS provider:**

> "Which provider manages (or will manage) your domain's DNS?"

Options:
- Cloudflare
- DigitalOcean DNS
- AWS Route 53
- Other (ask for provider name; generate best-effort config)

Then ask (DNS-specific):
- Domain name (e.g., `example.com`)
- Subdomain (e.g., `app`, `www`, or `@` for apex)

---

## Directory Structure

Always create:

```
terraform/
├── main.tf
├── variables.tf
├── outputs.tf
└── terraform.tfvars.example
```

Add to `.gitignore`:

```
terraform/.terraform/
terraform/.terraform.lock.hcl
terraform/terraform.tfstate
terraform/terraform.tfstate.backup
terraform/terraform.tfvars
```

---

## Terraform Configurations

Generate only the blocks that match the scenario. Mix and match server + DNS sections as needed.

---

### Server: DigitalOcean

**variables.tf additions**

```hcl
variable "do_token" {
  description = "DigitalOcean personal access token"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "DigitalOcean region slug"
  type        = string
  default     = "nyc3"
}

variable "droplet_size" {
  description = "DigitalOcean droplet size slug"
  type        = string
  default     = "s-1vcpu-2gb"
}

variable "app_name" {
  description = "Short name used for resource naming"
  type        = string
}
```

**main.tf additions — common provider block**

```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}
```

**main.tf — SSH key: existing key in DigitalOcean profile**

Use when the user already has an SSH key uploaded to their DigitalOcean account.

Add to `variables.tf`:

```hcl
variable "do_ssh_key_name" {
  description = "Name of the SSH key as it appears in the DigitalOcean control panel"
  type        = string
}
```

Add to `main.tf`:

```hcl
data "digitalocean_ssh_key" "app" {
  name = var.do_ssh_key_name
}
```

Reference in the droplet: `ssh_keys = [data.digitalocean_ssh_key.app.id]`

Add to `terraform.tfvars.example`:

```hcl
do_ssh_key_name = "my-laptop"   # DigitalOcean → Settings → Security → SSH Keys — exact name
```

**main.tf — SSH key: upload new key from local file**

Use when the user wants to upload a new SSH key.

Add to `variables.tf`:

```hcl
variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}
```

Add to `main.tf`:

```hcl
resource "digitalocean_ssh_key" "app" {
  name       = "${var.app_name}-key"
  public_key = file(var.ssh_public_key_path)
}
```

Reference in the droplet: `ssh_keys = [digitalocean_ssh_key.app.fingerprint]`

Add to `terraform.tfvars.example`:

```hcl
ssh_public_key_path = "~/.ssh/id_ed25519.pub"
```

**main.tf — droplet and firewall (same for both SSH key variants)**

```hcl
resource "digitalocean_droplet" "app" {
  name       = var.app_name
  region     = var.region
  size       = var.droplet_size
  image      = "ubuntu-24-04-x64"
  ssh_keys   = [<SSH_KEY_REFERENCE>]   # replace with the correct reference from above
  monitoring = true
}

resource "digitalocean_firewall" "app" {
  name        = "${var.app_name}-firewall"
  droplet_ids = [digitalocean_droplet.app.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
```

**outputs.tf additions**

```hcl
output "server_ip" {
  description = "Public IP of the provisioned server"
  value       = digitalocean_droplet.app.ipv4_address
}
```

**terraform.tfvars.example additions**

```hcl
do_token     = "dop_v1_..."   # DigitalOcean → API → Generate New Token (read+write)
region       = "nyc3"
droplet_size = "s-1vcpu-2gb"
# SSH key — include only the variable that matches the chosen option above:
# do_ssh_key_name     = "my-laptop"          # existing key in DigitalOcean profile
# ssh_public_key_path = "~/.ssh/id_ed25519.pub"  # new key to upload
```

---

### Server: Hetzner Cloud

**variables.tf additions**

```hcl
variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "location" {
  description = "Hetzner datacenter location"
  type        = string
  default     = "nbg1"
}

variable "server_type" {
  type    = string
  default = "cx22"
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "app_name" {
  type = string
}
```

**main.tf additions**

```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.0"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_ssh_key" "app" {
  name       = "${var.app_name}-key"
  public_key = file(var.ssh_public_key_path)
}

resource "hcloud_server" "app" {
  name        = var.app_name
  image       = "ubuntu-24.04"
  server_type = var.server_type
  location    = var.location
  ssh_keys    = [hcloud_ssh_key.app.id]
}

resource "hcloud_firewall" "app" {
  name = "${var.app_name}-firewall"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_firewall_attachment" "app" {
  firewall_id = hcloud_firewall.app.id
  server_ids  = [hcloud_server.app.id]
}
```

**outputs.tf additions**

```hcl
output "server_ip" {
  value = hcloud_server.app.ipv4_address
}
```

**terraform.tfvars.example additions**

```hcl
hcloud_token        = "..."   # Hetzner Cloud → Security → API Tokens → Generate API Token
location            = "nbg1"
server_type         = "cx22"
ssh_public_key_path = "~/.ssh/id_ed25519.pub"
```

---

### Server: AWS EC2

**variables.tf additions**

```hcl
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "app_name" {
  type = string
}
```

**main.tf additions**

```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "app" {
  key_name   = "${var.app_name}-key"
  public_key = file(var.ssh_public_key_path)
}

resource "aws_security_group" "app" {
  name = "${var.app_name}-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.app.key_name
  vpc_security_group_ids = [aws_security_group.app.id]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = var.app_name }
}

resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"
}
```

**outputs.tf additions**

```hcl
output "server_ip" {
  value = aws_eip.app.public_ip
}
```

**terraform.tfvars.example additions**

```hcl
aws_region          = "us-east-1"
instance_type       = "t3.small"
ssh_public_key_path = "~/.ssh/id_ed25519.pub"
```

Configure AWS credentials via environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) or an AWS profile — do not put credentials in `.tfvars`.

---

### DNS: Cloudflare

Use when the user's domain is managed via Cloudflare, whether the server IP comes from Terraform output or is an existing value.

**variables.tf additions**

```hcl
variable "cf_api_token" {
  description = "Cloudflare API token (Zone:Edit DNS permission)"
  type        = string
  sensitive   = true
}

variable "cf_zone_id" {
  description = "Cloudflare Zone ID for the domain"
  type        = string
}

variable "domain" {
  type = string
}

variable "subdomain" {
  description = "Subdomain (e.g. app, www) or @ for apex"
  type        = string
  default     = "@"
}

# Only needed when server IP is not coming from a Terraform resource in this config
variable "server_ip" {
  description = "Existing server IP (leave empty if server is provisioned in this config)"
  type        = string
  default     = ""
}
```

**main.tf additions**

```hcl
# Add cloudflare to required_providers if not already present:
# cloudflare = {
#   source  = "cloudflare/cloudflare"
#   version = "~> 4.0"
# }

provider "cloudflare" {
  api_token = var.cf_api_token
}

locals {
  # Use server resource IP when provisioned here; fall back to variable for DNS-only scenario
  resolved_server_ip = var.server_ip != "" ? var.server_ip : <SERVER_RESOURCE>.ipv4_address
}

resource "cloudflare_record" "app" {
  zone_id = var.cf_zone_id
  name    = var.subdomain
  content = local.resolved_server_ip
  type    = "A"
  ttl     = 60
  # proxied = false is intentional: Cloudflare proxy intercepts TLS and breaks
  # kamal-proxy's Let's Encrypt certificate issuance.
  proxied = false
}
```

Replace `<SERVER_RESOURCE>.ipv4_address` with the actual resource reference when server is also provisioned here (e.g., `digitalocean_droplet.app.ipv4_address`, `hcloud_server.app.ipv4_address`). For DNS-only scenario, the `locals` block collapses to just `var.server_ip`.

**outputs.tf additions**

```hcl
output "domain" {
  value = var.subdomain == "@" ? var.domain : "${var.subdomain}.${var.domain}"
}
```

**terraform.tfvars.example additions**

```hcl
cf_api_token = "..."   # Cloudflare → My Profile → API Tokens → Edit Zone DNS
cf_zone_id   = "..."   # Cloudflare → your domain → Overview → Zone ID (right sidebar)
domain       = "example.com"
subdomain    = "@"
# server_ip  = "1.2.3.4"  # uncomment only for DNS-only scenario
```

---

### DNS: DigitalOcean DNS

Use when the domain is managed via DigitalOcean's DNS (domain must already be added to the DO project).

**variables.tf additions**

```hcl
variable "domain" {
  type = string
}

variable "subdomain" {
  type    = string
  default = "@"
}

variable "server_ip" {
  description = "Existing server IP (leave empty if server is provisioned in this config)"
  type        = string
  default     = ""
}
```

**main.tf additions** (uses the existing `digitalocean` provider)

```hcl
locals {
  resolved_server_ip = var.server_ip != "" ? var.server_ip : digitalocean_droplet.app.ipv4_address
}

resource "digitalocean_domain" "app" {
  name = var.domain
}

resource "digitalocean_record" "app" {
  domain = digitalocean_domain.app.id
  type   = "A"
  name   = var.subdomain
  value  = local.resolved_server_ip
  ttl    = 60
}
```

**terraform.tfvars.example additions**

```hcl
domain    = "example.com"
subdomain = "@"
# server_ip = "1.2.3.4"  # uncomment only for DNS-only scenario
```

---

### DNS: AWS Route 53

Use when the domain is already registered and hosted in Route 53.

**variables.tf additions**

```hcl
variable "domain" {
  description = "Root domain already registered in Route 53"
  type        = string
}

variable "subdomain" {
  type    = string
  default = "@"
}

variable "server_ip" {
  description = "Existing server IP (leave empty if server is provisioned in this config)"
  type        = string
  default     = ""
}
```

**main.tf additions** (uses the existing `aws` provider)

```hcl
data "aws_route53_zone" "app" {
  name         = var.domain
  private_zone = false
}

locals {
  resolved_server_ip = var.server_ip != "" ? var.server_ip : aws_eip.app.public_ip
}

resource "aws_route53_record" "app" {
  zone_id = data.aws_route53_zone.app.zone_id
  name    = var.subdomain == "@" ? var.domain : "${var.subdomain}.${var.domain}"
  type    = "A"
  ttl     = 60
  records = [local.resolved_server_ip]
}
```

**terraform.tfvars.example additions**

```hcl
domain    = "example.com"
subdomain = "@"
# server_ip = "1.2.3.4"  # uncomment only for DNS-only scenario
```

---

## Server-Only Scenario: DNS After Provisioning

When the user already has DNS configured and only a server is provisioned via Terraform, after `terraform apply` completes:

1. Run `terraform output server_ip` to get the IP.
2. Tell the user to add an A record manually in their DNS provider:
   - **Type**: A
   - **Name**: subdomain (or `@` for apex)
   - **Value**: the server IP from step 1
   - **TTL**: 60 (or lowest available)
3. If the user's DNS provider is Cloudflare, DigitalOcean DNS, or Route 53, offer to extend the Terraform config with the DNS section above so the record is managed as code too.

---

## Applying the Configuration

When creating `terraform/terraform.tfvars`, write `app_name` at the top automatically (derived as described in the "Derive app_name" section). The user only needs to fill in tokens and preferences.

Instruct the user to run from the project root:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform/terraform.tfvars — fill in tokens and preferences
# app_name is already set, do not change it

cd terraform
terraform init
terraform plan
terraform apply
```

After apply, extract outputs:

```bash
terraform output server_ip    # if server was provisioned
terraform output domain       # if DNS was provisioned
```

These values become `<SERVER_IP>` and `<DOMAIN>` in `config/deploy.yml`.

---

## After Provisioning

Before returning to the main Kamal flow, instruct the user to:

1. **Wait for DNS propagation** (only if DNS was provisioned). The TTL is 60 s but full propagation can take a few minutes:
   ```bash
   dig +short <domain>
   # should return the server IP
   ```

2. **Confirm SSH access**:
   ```bash
   ssh root@<server_ip>
   ```
   If refused, wait 30–60 s and retry (cloud-init may still be running).

Once SSH works, return to **SKILL.md Step 3b** with the confirmed `<SERVER_IP>` and `<DOMAIN>`.

---

## Caveats

- **State file**: `terraform.tfstate` contains sensitive data. It is `.gitignore`d. For team use, configure a remote backend (S3, Terraform Cloud) in `main.tf`.
- **Cloudflare `proxied = false`**: intentional. Cloudflare's orange-cloud proxy intercepts TLS and breaks kamal-proxy's Let's Encrypt issuance.
- **Elastic IPs (AWS)**: `aws_eip` is required — EC2 instances get a new IP on every stop/start without it.
- **Hetzner ARM servers** (`cax*` types): set `builder.arch: arm64` in `config/deploy.yml` instead of `amd64`.
- **`terraform destroy`**: tears down all resources in the state file. Run only when intentionally decommissioning.
