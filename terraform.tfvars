aws_region         = "us-east-1"
project_prefix     = "YOUR-APP-ENV"
assets_bucket_name = "YOUR-APP-ENV-assets-UNIQUEID"
domain_name        = "YOUR-DOMAIN.example.com"
db_username        = "admin"

# Database configuration
db_name = "APP_DB_NAME"

tags = {
  Environment = "ENV_PLACEHOLDER" # production, staging, development, etc.
  Project     = "PROJECT_NAME_PLACEHOLDER"
  Owner       = "TEAM_NAME_PLACEHOLDER" # Team or Individual
  Terraform   = "true"
}
