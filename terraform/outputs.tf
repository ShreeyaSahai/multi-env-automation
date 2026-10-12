output "dev_url" {
  description = "Direct URL for DEV server"
  value       = "http://${aws_instance.servers["dev"].public_ip}"
}

output "prod_url" {
  description = "Direct URL for PROD server"
  value       = "http://${aws_instance.servers["prod"].public_ip}"
}

output "dev_public_ip" {
  value = aws_instance.servers["dev"].public_ip
}

output "prod_public_ip" {
  value = aws_instance.servers["prod"].public_ip
}