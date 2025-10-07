# Arquivo temporário para forçar limpeza de recursos órfãos
# Execute: terraform apply -target=null_resource.cleanup_resources
# Depois remova este arquivo e execute terraform apply normalmente

resource "null_resource" "cleanup_resources" {
  provisioner "local-exec" {
    command = <<-EOT
      # Deletar instância RDS se existir
      aws rds delete-db-instance \
        --db-instance-identifier "${var.project_name}-db-${var.environment}" \
        --skip-final-snapshot \
        --region "${var.aws_region}" || true
      
      # Aguardar deleção
      aws rds wait db-instance-deleted \
        --db-instance-identifier "${var.project_name}-db-${var.environment}" \
        --region "${var.aws_region}" || true
      
      # Forçar deleção do secret
      aws secretsmanager delete-secret \
        --secret-id "${var.project_name}-db-credentials-production" \
        --force-delete-without-recovery \
        --region "${var.aws_region}" || true
      
      # Esvaziar bucket S3
      BUCKET=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, '${var.project_name}-vpc-flow-logs-${var.environment}')].Name" --output text --region "${var.aws_region}")
      if [ ! -z "$BUCKET" ]; then
        aws s3 rm s3://$BUCKET --recursive || true
        aws s3api delete-objects \
          --bucket "$BUCKET" \
          --delete "$(aws s3api list-object-versions --bucket "$BUCKET" --output json --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" || true
      fi
      
      echo "Limpeza concluída!"
    EOT
  }
}
