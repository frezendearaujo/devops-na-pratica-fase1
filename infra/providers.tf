provider "aws" {
  region = var.region

  # Aplicadas automaticamente a todos os recursos deste modulo.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "dev"
      ManagedBy   = "Terraform"
    }
  }
}
