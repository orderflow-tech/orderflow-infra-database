#!/bin/bash

# Script para limpar recursos órfãos do AWS antes de executar terraform apply
# Execute este script antes de rodar o pipeline para resolver conflitos de estado

set -e

echo "🧹 Iniciando limpeza de recursos AWS órfãos..."

# Configurar variáveis
PROJECT_NAME="orderflow"
ENVIRONMENT="dev"
REGION="us-east-1"

echo "📋 Projeto: $PROJECT_NAME | Ambiente: $ENVIRONMENT | Região: $REGION"

# 1. Deletar instância RDS se existir (forçar)
echo "🗄️ Verificando instância RDS..."
RDS_INSTANCE="${PROJECT_NAME}-db-${ENVIRONMENT}"
if aws rds describe-db-instances --db-instance-identifier "$RDS_INSTANCE" --region "$REGION" >/dev/null 2>&1; then
    echo "⚠️ Instância RDS encontrada. Deletando com skip-final-snapshot..."
    aws rds delete-db-instance \
        --db-instance-identifier "$RDS_INSTANCE" \
        --skip-final-snapshot \
        --region "$REGION" || true
    
    echo "⏳ Aguardando deleção da instância RDS..."
    aws rds wait db-instance-deleted \
        --db-instance-identifier "$RDS_INSTANCE" \
        --region "$REGION" || true
else
    echo "✅ Nenhuma instância RDS encontrada"
fi

# 2. Deletar Parameter Group se existir
echo "🔧 Verificando Parameter Group..."
PARAM_GROUP="${PROJECT_NAME}-pg-${ENVIRONMENT}"
if aws rds describe-db-parameter-groups --db-parameter-group-name "$PARAM_GROUP" --region "$REGION" >/dev/null 2>&1; then
    echo "⚠️ Parameter Group encontrado. Deletando..."
    aws rds delete-db-parameter-group \
        --db-parameter-group-name "$PARAM_GROUP" \
        --region "$REGION" || true
else
    echo "✅ Nenhum Parameter Group encontrado"
fi

# 3. Deletar Subnet Group se existir
echo "🌐 Verificando DB Subnet Group..."
SUBNET_GROUP="${PROJECT_NAME}-db-subnet-group-${ENVIRONMENT}"
if aws rds describe-db-subnet-groups --db-subnet-group-name "$SUBNET_GROUP" --region "$REGION" >/dev/null 2>&1; then
    echo "⚠️ DB Subnet Group encontrado. Deletando..."
    aws rds delete-db-subnet-group \
        --db-subnet-group-name "$SUBNET_GROUP" \
        --region "$REGION" || true
else
    echo "✅ Nenhum DB Subnet Group encontrado"
fi

# 4. Limpar bucket S3 (esvaziar antes de deletar)
echo "🪣 Verificando buckets S3..."
BUCKET_PREFIX="${PROJECT_NAME}-vpc-flow-logs-${ENVIRONMENT}"
for bucket in $(aws s3api list-buckets --query "Buckets[?starts_with(Name, '$BUCKET_PREFIX')].Name" --output text --region "$REGION"); do
    if [ ! -z "$bucket" ]; then
        echo "⚠️ Bucket S3 encontrado: $bucket. Esvaziando..."
        
        # Deletar todas as versões dos objetos
        aws s3api delete-objects \
            --bucket "$bucket" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$bucket" \
                --output json \
                --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" \
            --region "$REGION" || true
        
        # Deletar marcadores de deleção
        aws s3api delete-objects \
            --bucket "$bucket" \
            --delete "$(aws s3api list-object-versions \
                --bucket "$bucket" \
                --output json \
                --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" \
            --region "$REGION" || true
        
        echo "✅ Bucket $bucket esvaziado"
    fi
done

# 5. Cancelar deleção pendente do Secrets Manager
echo "🔐 Verificando Secrets Manager..."
SECRET_NAME="${PROJECT_NAME}-db-credentials-production"
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region "$REGION" >/dev/null 2>&1; then
    echo "⚠️ Secret encontrado. Verificando se está agendado para deleção..."
    
    # Tentar restaurar se estiver agendado para deleção
    aws secretsmanager restore-secret \
        --secret-id "$SECRET_NAME" \
        --region "$REGION" || true
    
    # Forçar deleção imediata
    aws secretsmanager delete-secret \
        --secret-id "$SECRET_NAME" \
        --force-delete-without-recovery \
        --region "$REGION" || true
        
    echo "✅ Secret processado"
else
    echo "✅ Nenhum secret encontrado"
fi

# 6. Aguardar propagação
echo "⏳ Aguardando propagação das mudanças (30 segundos)..."
sleep 30

echo "✅ Limpeza concluída! Agora você pode executar terraform apply com segurança."
echo ""
echo "🚀 Próximos passos:"
echo "1. cd terraform/"
echo "2. terraform plan"
echo "3. terraform apply"
