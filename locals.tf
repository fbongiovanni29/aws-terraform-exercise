# I use locals instead of a variable with a map of defaults
# because it accepts multiple types
locals {
  # Values for each environment "dev" & "prod"
  envs = {
    "dev" = {
      subdomain = "dev"
      itype     = "t2.micro" # Smaller machine to save $$$ in development
      zones_and_cidrs = [    # 2 zones/instances in dev to save $$$
        {
          zone = "a"
          cidr = "10.0.1.0/24"
        },
        {
          zone = "b"
          cidr = "10.0.2.0/24"
        },
      ]
    }
    "prod" = {
      subdomain = "www"
      itype     = "t2.small" # Bigger machine in prod to handle load
      zones_and_cidrs = [    # 3 zones/instances in prod to handle load
        {
          zone = "a"
          cidr = "10.0.1.0/24"
        },
        {
          zone = "b"
          cidr = "10.0.2.0/24"
        },
        {
          zone = "c"
          cidr = "10.0.3.0/24"
        },
      ]
    }
  }
  # Set environment specific values
  subdomain       = local.envs[terraform.workspace].subdomain
  itype           = local.envs[terraform.workspace].itype
  zones_and_cidrs = local.envs[terraform.workspace].zones_and_cidrs

  ssl_policy   = "ELBSecurityPolicy-TLS-1-2-2017-01"
  region       = "us-east-1"
  ami          = "ami-003a61536c01a7373"
  public_ip    = true
  secgroupname = "Webserver-Sec-Group"
  # Set just the zones from zones_and_cidrs
  zones  = toset([for zc in local.zones_and_cidrs : zc.zone])
  domain = "fbongiovanni.click"
  common_tags = {
    Environment = upper(terraform.workspace)
    Managed     = "IAC"
    Name        = "aws-terraform-exercise-${terraform.workspace}"
  }

  protocols = {
    https = { port = 443 }
    http  = { port = 80 }
  }
  # Groups an array of each zone and each protocol
  # Makes it easier to add a new zone
  # May be a little fancy & unnecessary but I figured I'd showcase skills
  #
  # Outputs looks like:
  # [{"port" = "80", "protocol" = "http", "zone" = "a"}, ...],
  #
  # For clearer view run:
  #   $ terraform console
  #   > locals.protocols_and_zone
  protocols_and_zones = flatten([
    for protocol, value in local.protocols :
    [for zone in local.zones :
      tomap({ zone = zone, port = value.port, protocol = protocol }
    )]
  ])
}
