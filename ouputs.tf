output "ec2instances" {
  value = values(aws_instance.webserver)[*].public_ip
}

output "url" {
  value = aws_route53_record.domain.name
}

