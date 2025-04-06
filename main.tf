provider "aws" {
  region = var.aws_region
}

# VPC w/ subnets across multiple AZs
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  enable_vpn_gateway = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = var.tags
}

# Security Groups
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Controls access to the ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

# Request an ACM Certificate (Needs Route 53 zone)
resource "aws_acm_certificate" "cert" {
  count = var.enable_domain_features ? 1 : 0

  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method         = "DNS"

  # depends_on is implicitly handled by referencing the zone if created,
  # or handled by the validation resource needing the records.
  # depends_on = [aws_route53_zone.main] # Remove explicit depends_on here

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Controls access to web servers"
  vpc_id      = module.vpc.vpc_id

  ingress {
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Controls access to the database"
  vpc_id      = module.vpc.vpc_id

  ingress {
    protocol        = "tcp"
    from_port       = 3306
    to_port         = 3306
    security_groups = [aws_security_group.web.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = var.tags
}

# App Load Balancer
resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false

  tags = var.tags
}

resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    enabled             = true
    interval            = 30
    path                = "/"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    protocol            = "HTTP"
    matcher             = "200-299"
  }

  tags = var.tags
}

# HTTP Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  # CONDITIONAL Default Action
  default_action {
    # If domain features are enabled (meaning HTTPS listener will exist), redirect to HTTPS.
    # Otherwise (if only HTTP is available), forward directly to the target group.
    type = var.enable_domain_features ? "redirect" : "forward"

    # Only include 'redirect' block if redirecting
    dynamic "redirect" {
      for_each = var.enable_domain_features ? [1] : []
      content {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    target_group_arn = var.enable_domain_features ? null : aws_lb_target_group.app.arn
  }
}

resource "aws_lb_listener" "https" {
  count = var.enable_domain_features ? 1 : 0 # CONDITIONAL

  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.alb_ssl_policy
  # Reference the conditionally created validation resource
  certificate_arn = aws_acm_certificate_validation.cert[0].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Auto Scaling Group
resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-web-"
  image_id      = var.ami_id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.web.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.instance_profile.name
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    # Example: Placeholder for installing CloudWatch Agent, SSM Agent (often pre-installed),
    # fetching secrets, and starting the application.
    # This needs to be significantly expanded for a real application.
    yum update -y
    # Install CW Agent, configure it, start it
    # Install dependencies (node, python, java etc)
    # Get application code (e.g., from S3, CodeDeploy)
    # Fetch DB creds from Secrets Manager using aws cli (leveraging the IAM role)
    # Configure application
    # Start application service
    echo "Instance setup complete (placeholder)" > /var/www/html/index.html
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.project_name}-web" })
  }
}

resource "aws_autoscaling_group" "web" {
  name                = "${var.project_name}-asg"
  vpc_zone_identifier = module.vpc.private_subnets
  desired_capacity    = var.asg_desired_capacity
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.app.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "${var.project_name}-web"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

# Scale up policy
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "${var.project_name}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.web.name
}

# Scale down policy
resource "aws_autoscaling_policy" "scale_down" {
  name                   = "${var.project_name}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.web.name
}

# CloudWatch alarms
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This monitors high EC2 CPU usage"
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "${var.project_name}-low-cpu"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "120"
  statistic           = "Average"
  threshold           = "30"
  alarm_description   = "This metric monitors low EC2 CPU utilization"
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }
}

# DB Subnet Group Name Casing
resource "aws_db_subnet_group" "default" {
  name       = "${lower(var.project_name)}-db-subnet-group" # Use lower()
  subnet_ids = module.vpc.private_subnets
  tags       = var.tags
}

resource "aws_db_instance" "default" {
  allocated_storage      = 20
  db_name                = var.db_name
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = var.db_instance_class
  username               = var.db_username
  password               = var.db_password
  parameter_group_name   = "default.mysql8.0"
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.db.id]
  db_subnet_group_name   = aws_db_subnet_group.default.name

  tags = var.tags
}

# Assets S3 Bucket
resource "aws_s3_bucket" "assets" {
  bucket = var.assets_bucket_name

  tags = var.tags
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create CloudFront distribution for serving assets from S3
resource "aws_cloudfront_distribution" "assets" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    domain_name = aws_s3_bucket.assets.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.assets.bucket}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.assets.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.assets.bucket}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = var.tags
}

resource "aws_cloudfront_origin_access_identity" "assets" {
  comment = "access-identity-${var.assets_bucket_name}"
}

# Authorizing CloudFront for S3 bucket
resource "aws_s3_bucket_policy" "assets" {
  bucket = aws_s3_bucket.assets.id
  policy = jsonencode({
    Version = "2012-10-17",
    Id      = "PolicyForCloudFrontPrivateContent",
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal",
        Effect = "Allow",
        Principal = {
          Service = "cloudfront.amazonaws.com"
        },
        Action   = "s3:GetObject",
        Resource = "${aws_s3_bucket.assets.arn}/*",
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.assets.arn
          }
        }
      }
    ]
  })
}

# S3 Bucket for Terraform State
resource "aws_s3_bucket" "terraform_state" {
  bucket = "YOUR_S3_BUCKET_NAME_FOR_TERRAFORM_STATE" # MUST BE GLOBALLY UNIQUE -  consider using a project-specific prefix
  # bucket = "${lower(var.project_name)}-terraform-state" # Example using project_name, but ensure uniqueness

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  # Optional: Enable bucket policy to restrict access if needed.
  # For example, restrict access to specific IAM roles or accounts.
  # For simplicity, this example omits a restrictive bucket policy.
  # In a production scenario, consider implementing a more restrictive policy.

  tags = merge(var.tags, {
    Name        = "Terraform State Bucket"
    Description = "Bucket to store Terraform state files"
  })
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


# DynamoDB Table for Terraform State Locking
resource "aws_dynamodb_table" "terraform_state_lock" {
  name           = "terraform-state-locking" # You can customize the table name if needed
  billing_mode   = "PAY_PER_REQUEST" # Or "PROVISIONED" if you prefer provisioned capacity
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S" # String type
  }

  tags = merge(var.tags, {
    Name        = "Terraform State Locking Table"
    Description = "DynamoDB table for Terraform state locking"
  })
}

# IAM Role for EC2 Instances
resource "aws_iam_role" "instance_role" {
  name = "${var.project_name}-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = var.tags
}

# IAM Policy for required permissions (CloudWatch Logs, SSM, Secrets Manager)
resource "aws_iam_policy" "instance_policy" {
  name        = "${var.project_name}-instance-policy"
  description = "Policy for EC2 instances to access CloudWatch Logs, SSM, Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Required for CloudWatch Agent/Logs
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ],
        Resource = "arn:aws:logs:*:*:*" # Restrict to specific log groups
      },
      {
        # Recommended for SSM Agent & Session Manager
        Effect = "Allow",
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ],
        Resource = "*"
      },
      {
        # Required for SSM Get Parameters
        Effect = "Allow",
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ],
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/*" # Adjust path if needed
      },
      {
        # Required to fetch DB creds from Secrets Manager
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue"
        ],
        # IMPORTANT: Restrict this to the specific secrets your app needs!
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:*"
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

# Attach Policy to Role
resource "aws_iam_role_policy_attachment" "instance_policy_attach" {
  role       = aws_iam_role.instance_role.name
  policy_arn = aws_iam_policy.instance_policy.arn
}

# Attach AWS Managed Policy for SSM Core functionality
resource "aws_iam_role_policy_attachment" "instance_ssm_managed" {
  role       = aws_iam_role.instance_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create Instance Profile to attach Role to EC2
resource "aws_iam_instance_profile" "instance_profile" {
  name = "${var.project_name}-instance-profile"
  role = aws_iam_role.instance_role.name

  depends_on = [aws_iam_role.instance_role]
}

# Route53
resource "aws_route53_zone" "main" {
  count = var.enable_domain_features && var.create_route53_zone ? 1 : 0

  name = var.domain_name
  tags = var.tags
}

resource "aws_route53_record" "www" {
  # Only create if domain features ON *and* user wants TF to create zone
  count = var.enable_domain_features && var.create_route53_zone ? 1 : 0

  zone_id = aws_route53_zone.main[0].zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = var.enable_domain_features ? {
    # This expression creates a map only if the certificate resource exists (count > 0)
    for dvo in aws_acm_certificate.cert[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type

      zone_id = var.create_route53_zone ? aws_route53_zone.main[0].zone_id : data.aws_route53_zone.existing[0].zone_id
    }
  } : {}

  allow_overwrite = true # Still useful if records exist outside TF
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = each.value.zone_id
}

# Alternative: Data source if Route 53 Zone exists but isn't managed by this TF state
data "aws_route53_zone" "existing" {
  # Only look up if domain features are ON *and* user wants to use existing zone
  count = var.enable_domain_features && !var.create_route53_zone ? 1 : 0

  name         = var.domain_name
  private_zone = false
}

# Wait for Certificate Validation to Complete
resource "aws_acm_certificate_validation" "cert" {
  count = var.enable_domain_features ? 1 : 0 # CONDITIONAL

  certificate_arn = aws_acm_certificate.cert[0].arn
  # This list comprehension works fine - it will be empty if cert_validation creates 0 records
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

  # Add timeout if needed
  # timeouts {
  #    create = "20m"
  # }
}

# Output
output "alb_dns_name" {
  description = "The public DNS name of the Application Load Balancer."
  value       = aws_lb.app.dns_name
}

output "application_url" {
  description = "Primary URL for the application (HTTPS if domain enabled, HTTP otherwise)"
  value       = var.enable_domain_features ? "https://${var.domain_name}" : "http://${aws_lb.app.dns_name}"
}

output "cloudfront_domain_name" {
  description = "The domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.assets.domain_name
}

output "rds_endpoint" {
  description = "The connection endpoint for the RDS instance"
  value       = aws_db_instance.default.endpoint
}

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate"
  value       = one(aws_acm_certificate.cert[*].arn)
}

output "instance_profile_name" {
  description = "Name of the IAM Instance Profile for EC2 instances"
  value       = aws_iam_instance_profile.instance_profile.name
}
