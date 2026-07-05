terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name (used as prefix for all resource names)"
  type        = string
}

variable "tf_state_bucket" {
  description = "S3 bucket used for Terraform state and Lambda zip artifact"
  type        = string
}

variable "zip_key" {
  description = "S3 key for the Lambda deployment zip"
  type        = string
  default     = "lambda/function.zip"
}

# ---------------------------------------------------------------------------
# IAM role for Lambda
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.project_name}-lambda-exec"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ---------------------------------------------------------------------------
# Lambda function
# ---------------------------------------------------------------------------

resource "aws_lambda_function" "app" {
  function_name = "${var.project_name}-app"
  role          = aws_iam_role.lambda_exec.arn

  s3_bucket = var.tf_state_bucket
  s3_key    = var.zip_key

  handler = "lambda_handler.handler"
  runtime = "python3.11"

  timeout     = 30
  memory_size = 256

  environment {
    variables = {
      APP_ENV = "production"
    }
  }

  depends_on = [aws_iam_role_policy_attachment.lambda_basic_execution]
}

# ---------------------------------------------------------------------------
# Lambda Function URL (public, no auth)
# ---------------------------------------------------------------------------

resource "aws_lambda_function_url" "app" {
  function_name      = aws_lambda_function.app.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["*"]
    allow_methods = ["*"]
    allow_headers = ["*"]
  }
}

resource "aws_lambda_permission" "allow_function_url" {
  statement_id           = "AllowPublicFunctionURL"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.app.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "function_url" {
  description = "Public Lambda Function URL"
  value       = aws_lambda_function_url.app.function_url
}

output "function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.app.function_name
}