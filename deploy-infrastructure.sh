#!/bin/bash

echo "🚀 Deploying OrderFlow Database Infrastructure"
echo "============================================="

# Check if we're in the terraform directory
if [ ! -f "terraform.tfvars" ]; then
    echo "❌ Please run this script from the terraform directory"
    echo "Run: cd terraform && ../deploy-infrastructure.sh"
    exit 1
fi

# Check if AWS credentials are configured
echo "📋 Checking AWS credentials..."
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_SESSION_TOKEN" ]; then
    echo "❌ AWS credentials not found!"
    echo "Please run: source ../set-aws-credentials.sh"
    exit 1
fi

echo "✅ AWS credentials are configured"

# Check if Terraform is initialized
if [ ! -d ".terraform" ]; then
    echo "❌ Terraform not initialized. Please run the setup script first."
    echo "Run: ../setup-infrastructure.sh"
    exit 1
fi

# Display current configuration
echo ""
echo "📋 Current Configuration:"
echo "========================="
grep -E "^[^#]" terraform.tfvars

echo ""
echo "🔍 Running Terraform plan..."
terraform plan

echo ""
read -p "Do you want to proceed with the deployment? (yes/no): " confirm

if [ "$confirm" = "yes" ]; then
    echo ""
    echo "🚀 Deploying infrastructure..."
    terraform apply
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "🎉 Infrastructure deployed successfully!"
        echo ""
        echo "📋 Getting outputs..."
        terraform output
        
        echo ""
        echo "🔐 Database credentials are stored in AWS Secrets Manager"
        echo "Secret name: orderflow-db-credentials-dev"
        echo ""
        echo "To retrieve credentials:"
        echo "aws secretsmanager get-secret-value --secret-id orderflow-db-credentials-dev --region us-east-1"
        
    else
        echo "❌ Deployment failed!"
        exit 1
    fi
else
    echo "❌ Deployment cancelled by user"
fi