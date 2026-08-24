output "instance_public_ip" {
  description = "IP publico da instancia que executa a aplicacao."
  value       = aws_instance.app.public_ip
}

output "api_url" {
  description = "URL base da API de tarefas."
  value       = "http://${aws_instance.app.public_ip}"
}

output "health_check_url" {
  description = "URL do health check da aplicacao."
  value       = "http://${aws_instance.app.public_ip}/health"
}
