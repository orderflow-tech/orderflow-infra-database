#!/bin/bash

echo "🚀 Setting up OrderFlow Database Infrastructure"
echo "============================================="

# Step 1: Check if AWS credentials are configured
echo "📋 Step 1: Checking AWS credentials..."
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_SESSION_TOKEN" ]; then
    echo "❌ AWS credentials not found!"
    echo "Please run: source ./set-aws-credentials.sh"
    echo "Make sure to update the credentials in the script first!"
    exit 1
fi

echo "✅ AWS credentials are configured"
echo "Region: $AWS_REGION"
echo "Access Key: ${AWS_ACCESS_KEY_ID:0:20}..."

# Step 2: Create S3 bucket for Terraform state
echo ""
echo "📦 Step 2: Creating S3 bucket for Terraform state..."
aws s3 mb s3://orderflow-terraform-state --region us-east-1

if [ $? -eq 0 ]; then
    echo "✅ S3 bucket created successfully"
else
    # Check if bucket already exists
    if aws s3 ls s3://orderflow-terraform-state >/dev/null 2>&1; then
        echo "ℹ️  S3 bucket already exists"
    else
        echo "❌ Failed to create S3 bucket. Please check your AWS credentials."
        exit 1
    fi
fi

# Step 3: Enable versioning on the S3 bucket
echo ""
echo "🔄 Step 3: Enabling versioning on S3 bucket..."
aws s3api put-bucket-versioning \
    --bucket orderflow-terraform-state \
    --versioning-configuration Status=Enabled

if [ $? -eq 0 ]; then
    echo "✅ S3 bucket versioning enabled"
else
    echo "⚠️  Warning: Could not enable versioning"
fi

# Step 4: Navigate to terraform directory and initialize
echo ""
echo "🔧 Step 4: Initializing Terraform..."
cd terraform

terraform init

if [ $? -eq 0 ]; then
    echo "✅ Terraform initialized successfully"
else
    echo "❌ Terraform initialization failed"
    exit 1
fi

# Step 5: Validate Terraform configuration
echo ""
echo "🔍 Step 5: Validating Terraform configuration..."
terraform validate

if [ $? -eq 0 ]; then
    echo "✅ Terraform configuration is valid"
else
    echo "❌ Terraform configuration is invalid"
    exit 1
fi

# Step 6: Plan the infrastructure
echo ""
echo "📋 Step 6: Planning infrastructure deployment..."
terraform plan

if [ $? -eq 0 ]; then
    echo "✅ Terraform plan completed successfully"
    echo ""
    echo "🎯 Next steps:"
    echo "1. Review the plan above"
    echo "2. If everything looks good, run: terraform apply"
    echo "3. Type 'yes' when prompted to confirm the deployment"
else
    echo "❌ Terraform plan failed"
    exit 1
fi

echo ""
echo "🎉 Setup completed successfully!"
echo "Your infrastructure is ready to be deployed."