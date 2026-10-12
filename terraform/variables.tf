variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "my_ip" {
  description = "Your public IPv4 address in CIDR notation for SSH access"
  type        = string
  default     = "0.0.0.0/0"
}

variable "environments" {
  description = "Map of environments to provision"
  type = map(object({
    instance_type = string
    banner_color  = string
  }))
  default = {
    dev = {
      instance_type = "t3.micro"
      banner_color  = "amber"
    }
    prod = {
      instance_type = "t3.micro"
      banner_color  = "emerald"
    }
  }
}