aws_region = "us-east-1"
project_prefix = "YOUR-APP-ENV"  # Replace with your app name and environment, e.g., "myapp-prod"
assets_bucket_name = "YOUR-APP-ENV-assets-UNIQUEID"  # Must be globally unique, e.g., "myapp-prod-assets-781234"
domain_name = "YOUR-DOMAIN.example.com"  # Replace with your actual domain

# Database configuration
db_name       = "APP_DB_NAME"

# Set via environment variable or secrets manager
# db_username   = "APP_DB_USER"  
# db_password   = "PASSWORD"  

# Resource tags
tags = {
  Environment = "ENV_PLACEHOLDER"  # production, staging, development, etc.
  Project = "PROJECT_NAME_PLACEHOLDER" 
  Owner = "TEAM_NAME_PLACEHOLDER" # Team or Individual
  Terraform = "true"
}