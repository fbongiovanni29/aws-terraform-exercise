# PLEASE READ!!!
# Normally, for posterity & reusability, I'd  break this out into the following modules:
#   * networking
#   * dns
#   * compute
#   * waf
#
# As a time savings measure & for ease of development of this exercise I chose not to.

# VPC for environment's subnets
resource "aws_vpc" "main" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = local.common_tags
}

# Create a subnet for each zone with their given cidr
resource "aws_subnet" "main" {
  for_each = { for zc in local.zones_and_cidrs : zc.zone => zc }

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr
  availability_zone = "${local.region}${each.value.zone}"

  tags = local.common_tags
}

# Internet Gateway for environment
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# Egress Only Internet Gateway for environment
resource "aws_egress_only_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# Route traffic to Internet Gateways
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    egress_only_gateway_id = aws_egress_only_internet_gateway.main.id
  }

  tags = local.common_tags
}

# Associate route tables with each zonal subnets
resource "aws_route_table_association" "assoc" {
  for_each = local.zones

  route_table_id = aws_route_table.main.id
  subnet_id      = aws_subnet.main[each.key].id
}

# Sec Group to allow SSH, HTTP, HTTPS & Egress
resource "aws_security_group" "webserver-sg" {
  name        = local.secgroupname
  description = "Security Group: ${local.secgroupname}"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    #tfsec:ignore:aws-vpc-no-public-ingress-sgr
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    protocol    = "tcp"
    to_port     = 80
    #tfsec:ignore:aws-vpc-no-public-ingress-sgr
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    protocol    = "tcp"
    to_port     = 443
    #tfsec:ignore:aws-vpc-no-public-ingress-sgr
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    #tfsec:ignore:aws-vpc-no-public-egress-sgr
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# TLS Private key for key pair
resource "tls_private_key" "key" {
  algorithm = "RSA"
}

# Pair public key
resource "aws_key_pair" "key_pair" {
  key_name   = terraform.workspace
  public_key = tls_private_key.key.public_key_openssh

  tags = local.common_tags
}

# Zonal ec2 instances running the web server ami
resource "aws_instance" "webserver" {
  for_each = local.zones

  ami                         = local.ami
  instance_type               = local.itype
  subnet_id                   = aws_subnet.main[each.key].id
  associate_public_ip_address = local.public_ip
  key_name                    = aws_key_pair.key_pair.key_name


  vpc_security_group_ids = [
    aws_security_group.webserver-sg.id
  ]

  root_block_device {
    encrypted             = true
    delete_on_termination = true
    volume_size           = 50
    volume_type           = "gp2"
    # iops not supported for gp2
    # Other types are expensive
    # iops                = 150
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = merge({
    Server = "SERVER${upper(each.key)}"
    OS     = "DEBIAN"
    },
    local.common_tags
  )

  depends_on = [aws_subnet.main, aws_security_group.webserver-sg]
}

# Load balance each instance in their corresponding subnet
resource "aws_lb" "main" {
  name = terraform.workspace
  #tfsec:ignore:aws-elb-alb-not-public
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.webserver-sg.id]
  subnets            = [for subnet in aws_subnet.main : subnet.id]

  # Allows deletion for debugging in DEV environments
  # Protects in higher environments
  enable_deletion_protection = terraform.workspace != "dev"
  drop_invalid_header_fields = true


  tags = local.common_tags

  depends_on = [aws_subnet.main]

  lifecycle {
    create_before_destroy = true
  }
}

# Target groups for HTTP & HTTPS
resource "aws_lb_target_group" "web" {
  for_each = local.protocols

  name     = "${each.key}-${terraform.workspace}"
  port     = each.value["port"]
  protocol = upper(each.key)
  vpc_id   = aws_vpc.main.id

  tags = local.common_tags
}

# Attach target groups to HTTP & HTTPS each in all zones
resource "aws_lb_target_group_attachment" "protocol" {
  for_each = { for pz in local.protocols_and_zones : "${pz.protocol}-${pz.zone}" => pz }

  target_group_arn = aws_lb_target_group.web[each.value.protocol].arn
  target_id        = aws_instance.webserver[each.value.zone].id
  port             = each.value.port
}

# Forward HTTPS
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = local.ssl_policy
  certificate_arn   = aws_acm_certificate.cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web["https"].arn
  }

  tags = local.common_tags
}

# Redirect HTTP to HTTPS
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = local.common_tags
}

# Managed domain TLS certificate
resource "aws_acm_certificate" "cert" {
  domain_name       = "${local.subdomain}.${trim(data.aws_route53_zone.main.name, ".")}"
  validation_method = "DNS"

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

# Read data from my route53 zone fbongiovanni.click.
data "aws_route53_zone" "main" {
  name = "${local.domain}."
}

# A Record pointing to load balancer
resource "aws_route53_record" "domain" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${local.subdomain}.${trim(data.aws_route53_zone.main.name, ".")}"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# Alias root domain as full domain
resource "aws_route53_record" "root-domain" {
  count = local.subdomain == "www" ? 1 : 0

  name    = trim(aws_route53_record.domain.name, "www.")
  type    = "A"
  zone_id = data.aws_route53_zone.main.zone_id

  alias {
    evaluate_target_health = true
    name                   = aws_route53_record.domain.name
    zone_id                = data.aws_route53_zone.main.zone_id
  }
}

# Records to validate TLS certificate
resource "aws_route53_record" "cert-validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.main.zone_id

}

# WAF WEB ACLS
# Contains multiple managed waf rules that
# helps protect your web applications or APIs against
# common web exploits and bots that may affect availability,
# compromise security, or consume excessive resources.
#
# You can test by checking you receive a "403 forbidden"
# when hitting the site from the Tor browser
resource "aws_wafv2_web_acl" "managed-acls" {
  name  = terraform.workspace
  scope = "REGIONAL"
  tags  = local.common_tags

  default_action {
    allow {
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesAmazonIpReputationList"
    priority = 0

    override_action {

      none {}
    }

    statement {

      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "AWS-AWSManagedRulesAmazonIpReputationList"
      sampled_requests_enabled   = false
    }
  }
  rule {
    name     = "AWS-AWSManagedRulesAnonymousIpList"
    priority = 1

    override_action {

      none {}
    }

    statement {

      managed_rule_group_statement {
        name        = "AWSManagedRulesAnonymousIpList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "AWS-AWSManagedRulesAnonymousIpList"
      sampled_requests_enabled   = false
    }
  }
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {

      none {}
    }

    statement {

      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "AWS-AWSManagedRulesCommonRuleSet"
      sampled_requests_enabled   = false
    }
  }
  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3

    override_action {

      none {}
    }

    statement {

      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
      sampled_requests_enabled   = false
    }
  }
  rule {
    name     = "AWS-AWSManagedRulesLinuxRuleSet"
    priority = 4

    override_action {

      none {}
    }

    statement {

      managed_rule_group_statement {
        name        = "AWSManagedRulesLinuxRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "AWS-AWSManagedRulesLinuxRuleSet"
      sampled_requests_enabled   = false
    }
  }
  rule {
    name     = "AWS-AWSManagedRulesUnixRuleSet"
    priority = 5

    override_action {

      none {}
    }

    statement {

      managed_rule_group_statement {
        name        = "AWSManagedRulesUnixRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "AWS-AWSManagedRulesUnixRuleSet"
      sampled_requests_enabled   = false
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "waf"
    sampled_requests_enabled   = false
  }
}

# Associate WAF ACLs with Load Balancer
resource "aws_wafv2_web_acl_association" "main" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.managed-acls.arn
}
