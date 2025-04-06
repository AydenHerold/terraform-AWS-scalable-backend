# Terraform AWS Web Application Infrastructure

This repository contains Terraform code to provision a scalable and highly available web application infrastructure on AWS. It includes networking, compute, database, load balancing, CDN, security, and optional DNS/HTTPS configuration.

## Architecture Overview

This Terraform configuration creates the following core components:

1.  **VPC:** A custom Virtual Private Cloud (VPC) with public and private subnets spread across multiple Availability Zones (AZs) for high availability.
2.  **Networking:**
    *   Internet Gateway for public subnets.
    *   NAT Gateways (one per AZ) in public subnets to allow outbound internet access for resources in private subnets.
    *   Route tables for proper traffic routing.
3.  **Load Balancing:** An Application Load Balancer (ALB) in public subnets to distribute incoming traffic.
    *   Listens on HTTP (port 80).
    *   Optionally listens on HTTPS (port 443) if domain features are enabled.
    *   Redirects HTTP to HTTPS if HTTPS is enabled.
4.  **Compute:** An Auto Scaling Group (ASG) managing EC2 instances within private subnets.
    *   Uses a Launch Template to define instance configuration (AMI, instance type, user data, IAM role).
    *   Scales based on CPU utilization CloudWatch alarms.
5.  **Database:** An RDS MySQL instance running in private subnets.
    *   Uses a DB Subnet Group spanning multiple AZs.
6.  **Static Assets:**
    *   An S3 bucket for storing static website/application assets (e.g., JS, CSS, images).
    *   A CloudFront distribution configured to serve assets from the S3 bucket via an Origin Access Identity (OAI), keeping the bucket private.
7.  **Security:**
    *   Security Groups to control traffic flow:
        *   `alb-sg`: Allows HTTP/HTTPS traffic from the internet to the ALB.
        *   `web-sg`: Allows HTTP traffic from the ALB to the EC2 instances.
        *   `db-sg`: Allows MySQL traffic (port 3306) from the EC2 instances to the RDS instance.
    *   IAM Role and Instance Profile for EC2 instances, granting permissions for CloudWatch Logs, SSM (including Session Manager), Parameter Store, and Secrets Manager.
8.  **DNS & HTTPS (Optional):**
    *   An ACM Certificate for the specified domain name (if `enable_domain_features` is true).
    *   Route 53 DNS records for the domain and ACM validation (if `enable_domain_features` is true). Supports creating a new Route 53 zone or using an existing one.

**(Optional but Recommended) Architecture Diagram:**
                   +-----------------------+
                   |       Internet        |
                   +-----------+-----------+
                               |
                               v
                +----------------------------+
                | Route 53 (Optional - DNS)  |
                +----------------------------+
                               |
                               v
                +----------------------------+
                |  Application Load Balancer |
                |   (Public Subnets)         |
                +------------+---------------+
                             |
                             v
                   +-------------------+
                   |   EC2 Instances   |
                   |  (Auto Scaling)   |
                   | (Private Subnets) |
                   +--------+----------+
                            |
                            v
                     +-------------+
                     |    RDS      |
                     |  Database   |
                     | (Private)   |
                     +-------------+

[User Browser]
       |
       v
+---------------+       +------------------+
|   CloudFront  | <-->  |     S3 Bucket    |
| (Edge Loc.)   |       |  (Private via    |
+---------------+       | Origin Access ID)|
                        +------------------+


## Features

*   **High Availability:** Multi-AZ deployment for VPC subnets, ASG, and RDS.
*   **Scalability:** Auto Scaling Group adjusts capacity based on CPU load.
*   **Security:** Resources placed in private subnets where possible, with strict Security Group rules. IAM roles follow the principle of least privilege. S3 bucket access restricted via OAI.
*   **Cost-Effectiveness:** Uses NAT Gateways instead of NAT Instances, option for cost-effective instance types (configurable).
*   **Automation:** Fully deployable via Terraform.
*   **CI/CD Integration:** Includes a GitHub Actions workflow for automated testing (plan on PR) and deployment (apply on merge to `main`), including application asset deployment to S3/CloudFront.
*   **Optional Domain/HTTPS:** Easily enable custom domain names and HTTPS via ACM and Route 53 integration using feature flags (`enable_domain_features`, `create_route53_zone`).

## Prerequisites

1.  **Terraform:** Install Terraform (version specified in `deploy.yml` or compatible).
2.  **AWS Account:** An active AWS account.
3.  **AWS Credentials:** Configure AWS credentials locally (e.g., via `~/.aws/credentials`, environment variables) for manual deployment *OR* set up OIDC for the GitHub Actions workflow (see CI/CD section).
4.  **Route 53 Hosted Zone (Optional):** If using `enable_domain_features = true` and `create_route53_zone = false`, you need an existing public Route 53 hosted zone for your domain in your AWS account.
5.  **GitHub Secrets & Variables (for CI/CD):**
    *   `AWS_ROLE_TO_ASSUME`: (Secret) The ARN of the IAM Role GitHub Actions will assume via OIDC.
    *   `DB_PASSWORD`: (Secret) The password for the RDS database administrator user.
    *   `AWS_REGION`: (Variable) The AWS region to deploy to (e.g., `us-east-1`).
    *   `ASSETS_BUCKET_NAME`: (Variable) The name of the S3 bucket for static assets (must match `assets_bucket_name` in `terraform.tfvars`).
    *   `CLOUDFRONT_DISTRIBUTION_ID`: (Variable) The ID of the CloudFront distribution created by Terraform (Needed for cache invalidation). You might need to run Terraform once to get this ID and then add it as a variable.

## Configuration

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/AydenHerold/terraform-AWS-scalable-backend.git
    ```
2.  **Configure Variables:**
    *   Create a `terraform.tfvars` file (or modify the existing one).
    *   **Required Variables:**
        *   `project_name`: A unique, lowercase name prefix for your resources (e.g., `my-app-prod`).
        *   `assets_bucket_name`: A globally unique name for the S3 assets bucket.
        *   `db_name`: The name for the database inside the RDS instance.
        *   `db_username`: The administrator username for the RDS instance.
        *   `db_password`: The administrator password for the RDS instance. **It is strongly recommended to manage this via environment variables or secrets management, not hardcoded in `.tfvars` for production.** See the CI/CD section for handling this in GitHub Actions. For local runs, use `TF_VAR_db_password="yourpassword" terraform apply`.
    *   **Optional Domain/HTTPS:**
        *   To enable HTTPS and custom domain features, set `enable_domain_features = true`.
        *   Set `domain_name` to your desired domain (e.g., `"myapp.example.com"`).
        *   If you want Terraform to create a *new* Route 53 public hosted zone for this domain, set `create_route53_zone = true`.
        *   If you already have a Route 53 public hosted zone for this domain in your AWS account and want Terraform to use it (for creating ALB/validation records), keep `create_route53_zone = false`.
    *   **Other Variables:** Review `variables.tf` and override defaults in `terraform.tfvars` as needed (e.g., `aws_region`, `instance_type`, `ami_id`, `db_instance_class`, `tags`). Ensure `ami_id` is valid for your chosen `aws_region`.

## Deployment

### Manual Deployment

1.  **Initialize Terraform:**
    ```bash
    terraform init
    ```
2.  **Plan Deployment:** Review the changes Terraform will make.
    ```bash
    # Use -var-file if you didn't name it terraform.tfvars
    terraform plan -var-file=terraform.tfvars

    # If setting password via env var:
    export TF_VAR_db_password="your-secure-password"
    terraform plan -var-file=terraform.tfvars
    ```
3.  **Apply Changes:** Provision the infrastructure.
    ```bash
    # Use -var-file if you didn't name it terraform.tfvars
    # You will be prompted for the password if not set via env var
    terraform apply -var-file=terraform.tfvars

    # If setting password via env var:
    export TF_VAR_db_password="your-secure-password"
    terraform apply -var-file=terraform.tfvars -auto-approve # Use -auto-approve cautiously
    ```

### CI/CD Deployment (GitHub Actions)

This repository includes a `.github/workflows/deploy.yml` workflow:

1.  **Setup OIDC:** Configure AWS IAM OIDC identity provider for GitHub Actions. Create an IAM Role that the GitHub Actions workflow can assume (`AWS_ROLE_TO_ASSUME`). This role needs permissions to manage all the resources defined in the Terraform code and permissions for the `deploy-app` job (S3 PutObject, DeleteObject, ListBucket; CloudFront CreateInvalidation).
2.  **Configure Secrets & Variables:** Add the required secrets (`AWS_ROLE_TO_ASSUME`, `DB_PASSWORD`) and variables (`AWS_REGION`, `ASSETS_BUCKET_NAME`, `CLOUDFRONT_DISTRIBUTION_ID`) to your GitHub repository settings.
3.  **Workflow:**
    *   **On Pull Request (to `main`):** The workflow runs `terraform init`, `validate`, and `plan`. The plan output is posted as a comment on the PR.
    *   **On Push (to `main`):** The workflow runs `terraform init`, `validate`, and `terraform apply -auto-approve`, deploying the infrastructure changes. It then runs the `deploy-app` job.
4.  **Application Deployment (`deploy-app` Job):** After a successful `terraform apply` on the `main` branch, this job:
    *   Checks out the code.
    *   Sets up Node.js (assuming a Node.js frontend project in `./app`).
    *   Installs dependencies (`npm ci` in `./app`).
    *   Builds the application (`npm run build` in `./app`).
    *   Syncs the contents of `./app/build` to the S3 assets bucket specified by the `ASSETS_BUCKET_NAME` variable.
    *   Creates a CloudFront cache invalidation for `/*` on the distribution specified by `CLOUDFRONT_DISTRIBUTION_ID`.

## Resources Created

*   AWS VPC and associated networking components (Subnets, Route Tables, IGW, NAT Gateways)
*   AWS Application Load Balancer (ALB), Target Group, Listeners (HTTP/HTTPS)
*   AWS Auto Scaling Group (ASG), Launch Template
*   AWS EC2 Instances (managed by ASG)
*   AWS Security Groups (ALB, Web, DB)
*   AWS RDS DB Instance, DB Subnet Group
*   AWS S3 Bucket (for static assets)
*   AWS CloudFront Distribution, Origin Access Identity (OAI)
*   AWS IAM Role, Instance Profile, Policy (for EC2 instances)
*   AWS CloudWatch Metric Alarms (for ASG scaling)
*   AWS ACM Certificate (Conditional)
*   AWS Route 53 Hosted Zone (Conditional)
*   AWS Route 53 Records (Conditional)

## Outputs

After successful deployment, Terraform will output:

*   `alb_dns_name`: The public DNS name of the Application Load Balancer.
*   `application_url`: The primary URL to access the application (HTTPS if domain enabled, HTTP otherwise).
*   `cloudfront_domain_name`: The domain name of the CloudFront distribution (for accessing static assets).
*   `rds_endpoint`: The connection endpoint for the RDS database instance.
*   `acm_certificate_arn`: ARN of the ACM certificate (if created).
*   `instance_profile_name`: Name of the IAM Instance Profile attached to EC2 instances.

## Security Considerations

*   **Secrets Management:** The `db_password` is sensitive. Avoid committing it directly. Use environment variables for local testing (`TF_VAR_db_password`) and GitHub Secrets for CI/CD. Consider using AWS Secrets Manager to store the DB password and retrieve it within the EC2 instance's user data/application code using the provided IAM role.
*   **IAM Permissions:** The IAM role for EC2 instances grants access to CloudWatch Logs, SSM, Parameter Store, and Secrets Manager. Review and restrict resource ARNs in the `aws_iam_policy.instance_policy` where possible (especially for Secrets Manager).
*   **Security Groups:** Ingress rules are restricted (e.g., DB only accepts traffic from the Web SG). Review CIDR blocks (e.g., ALB ingress) and tighten if possible based on your needs.
*   **S3 Bucket Security:** The assets bucket is private, accessible only via CloudFront using OAI. Public access is explicitly blocked.
*   **User Data:** The `user_data` in the launch template is a basic placeholder. Ensure your actual user data script securely handles application setup, configuration fetching (e.g., DB credentials from Secrets Manager), and service startup.

## Notes

*   **EC2 User Data:** The `user_data` script in `aws_launch_template.web` is a placeholder. You **must** replace it with your actual application deployment and configuration steps (e.g., installing dependencies, fetching code, configuring environment variables, starting the application server, installing CloudWatch Agent).
*   **Application Code:** This Terraform setup provisions the infrastructure. You need a separate process to deploy your application code *onto* the EC2 instances (e.g., via User Data, CodeDeploy, Packer+AMI). The CI/CD workflow includes deployment of *static frontend assets* to S3/CloudFront, but not the backend application code to EC2.
