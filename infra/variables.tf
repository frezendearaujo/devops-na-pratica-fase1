variable "region" {
  description = "Regiao da AWS onde a infraestrutura sera provisionada."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto, usado nas tags e no nome dos recursos."
  type        = string
  default     = "devops-na-pratica-fase1"
}

variable "instance_type" {
  description = "Tipo da instancia EC2 que executa a aplicacao."
  type        = string
  default     = "t3.micro"
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "Bloco CIDR da subnet publica."
  type        = string
  default     = "10.0.1.0/24"
}
