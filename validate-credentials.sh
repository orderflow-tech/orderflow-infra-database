#!/bin/bash

echo "🔍 AWS Credentials Validator"
echo "=========================="

# Check if credentials are set
if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_SESSION_TOKEN" ]; then
    echo "❌ AWS credentials not found!"
    echo ""
    echo "Steps to fix:"
    echo "1. Edit set-aws-credentials.sh with your NEW AWS Lab credentials"
    echo "2. Run: source ./set-aws-credentials.sh"
    echo "3. Run this script again: ./validate-credentials.sh"
    exit 1
fi

# Check if credentials are still placeholders
if [[ "$AWS_ACCESS_KEY_ID" == *"SUBSTITUA"* ]] || [[ "$AWS_SECRET_ACCESS_KEY" == *"SUBSTITUA"* ]]; then
    echo "❌ Credentials are still placeholders!"
    echo ""
    echo "Please update set-aws-credentials.sh with your actual AWS Lab credentials"
    exit 1
fi

echo "✅ AWS credentials are loaded"
echo "Region: ${AWS_REGION:-us-east-1}"
echo "Access Key: ${AWS_ACCESS_KEY_ID:0:20}..."

# Test AWS connectivity
echo ""
echo "🔗 Testing AWS connectivity..."

# Test with a simple AWS command
aws sts get-caller-identity > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✅ AWS credentials are valid!"
    echo ""
    echo "🎯 Account Info:"
    aws sts get-caller-identity --output table
    echo ""
    echo "🚀 You can now run: ./setup-infrastructure.sh"
else
    echo "❌ AWS credentials are invalid or expired!"
    echo ""
    echo "Please get fresh credentials from your AWS Lab and update set-aws-credentials.sh"
    exit 1
fi