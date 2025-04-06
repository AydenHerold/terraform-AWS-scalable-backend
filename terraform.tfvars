# terraform.tfvars

aws_region = "us-east-1"
project_name = "my-web-app-dev" # Example: MUST BE LOWERCASE
assets_bucket_name = "my-web-app-dev-assets"
db_name     = "webappdb" 
db_username = "dbadmin" 

# --- Optional Domain Features (Defaults to disabled) ---
# enable_domain_features = false # (Default) Keep domain/HTTPS features off
# domain_name            = "example.local" # (Default placeholder) - Only relevant if enable_domain_features = true
# create_route53_zone    = false # (Default) - Only relevant if enable_domain_features = true

# Example if ENABLING domain features and using an EXISTING Route 53 zone:
# enable_domain_features = true
# domain_name            = "my-actual-domain.com" # Replace with your real domain
# create_route53_zone    = false # Use existing zone

# Example if ENABLING domain features and letting Terraform CREATE the Route 53 zone:
# enable_domain_features = true
# domain_name            = "my-actual-domain.com" # Replace with your real domain
# create_route53_zone    = true # Terraform will create the zone

# --- Tags ---
tags = {
  Environment = "development"         # E.g., production, staging, development
  Project     = "MyWebApp"            # E.g., Name of the overall project
  Owner       = "WebAppTeam"          # E.g., Team or Individual responsible
  Terraform   = "true"
}

# --- Other Overrides (Optional) ---
# instance_type = "t3.small"
# asg_desired_capacity = 3
# db_instance_class = "db.t3.small"
