#!/bin/bash
# Script para configurar credenciais AWS do LAB
# ⚠️ IMPORTANTE: SUBSTITUA PELAS SUAS CREDENCIAIS DO AWS LAB
# Executar: source ./set-aws-credentials.sh

export AWS_ACCESS_KEY_ID="SUBSTITUA_PELA_SUA_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="SUBSTITUA_PELA_SUA_SECRET_KEY"
export AWS_SESSION_TOKEN="SUBSTITUA_PELO_SEU_SESSION_TOKEN"
export AWS_REGION="us-east-1"

# Gere o secret em outro terminal: openssl rand -base64 32
export TF_VAR_jwt_secret="SUBSTITUA_PELO_SEU_JWT_SECRET"

echo "✅ Credenciais AWS configuradas!"
echo "Região: $AWS_REGION"
echo "Access Key: ${AWS_ACCESS_KEY_ID:0:20}..."