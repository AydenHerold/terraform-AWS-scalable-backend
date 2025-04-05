# Terraform AWS Scalable Backend Infrastructure

This project provisions a scalable and resilient backend infrastructure on AWS using Terraform. It sets up a multi-tier architecture suitable for deploying web applications like blogs, forums, or e-commerce platforms, focusing on high availability, scalability, and automation.

**Note:** This Terraform code deploys the *infrastructure* components (networking, servers, database, load balancer, etc.). It includes a basic CI/CD pipeline via GitHub Actions for infrastructure deployment and a placeholder for frontend asset deployment. The actual *backend application deployment* to the EC2 instances needs to be implemented separately within the CI/CD pipeline or instance user data.

## Features

*   **High Availability:**
    *   VPC spanning multiple Availability Zones (AZs).
    *   Public and Private Subnets across AZs.
    *   Application Load Balancer (ALB) distributing traffic across AZs.
    *   Auto Scaling Group (ASG) maintaining desired instance count across AZs.
    *   RDS Database Instance configured for Multi-AZ deployment.
*   **Scalability:**
    *   Auto Scaling Group automatically adjusts the number of EC2 instances based on CPU load (configurable).
    *   Application Load Balancer handles varying traffic loads.
*   **Security:**
    *   Resources deployed within a custom VPC.
    *   Network segmentation using Public and Private Subnets.
    *   Security Groups restricting traffic between tiers (ALB -> Web, Web -> DB).
    *   HTTPS enforced on the Application Load Balancer using AWS Certificate Manager (ACM).
    *   Dedicated IAM Role for EC2 instances with least-privilege permissions for accessing necessary AWS services (CloudWatch, SSM, Secrets Manager).
    *   Private S3 Bucket for static assets, served securely via CloudFront Origin Access Identity (OAI).
*   **Automation:**
    *   Infrastructure defined as code using Terraform.
    *   CI/CD pipeline using GitHub Actions for automated Terraform deployment (`plan` on PR, `apply` on merge to `main`).
*   **Managed Services:**
    *   AWS RDS for managed relational database (MySQL).
    *   AWS S3 & CloudFront for scalable and secure static asset hosting.
    *   AWS Route 53 for DNS management.
    *   AWS Certificate Manager (ACM) for SSL/TLS certificates.

## Architecture Overview

1.  **DNS:** (Optional) Route 53 manages the domain's DNS records.
2.  **User Traffic:** Hits Route 53, which resolves to the Application Load Balancer (ALB).
3.  **Load Balancer (ALB):**
    *   Listens on HTTPS (port 443) using an ACM certificate.
    *   Redirects HTTP (port 80) traffic to HTTPS.
    *   Distributes incoming traffic across healthy EC2 instances in the private subnets.
    *   Resides in public subnets.
4.  **Compute (EC2 Auto Scaling Group):**
    *   EC2 instances run the backend application.
    *   Launched from a Launch Template which specifies the AMI, instance type, security group, and **IAM Instance Profile**.
    *   Managed by an Auto Scaling Group spanning multiple AZs within private subnets.
    *   Scales based on CloudWatch CPU utilization alarms.
    *   Instances have an IAM Role granting permissions to access CloudWatch Logs, SSM, and Secrets Manager (for retrieving DB credentials securely).
5.  **Database (RDS):**
    *   Managed MySQL database instance.
    *   Deployed in a Multi-AZ configuration for high availability.
    *   Resides in private subnets.
    *   Accessible only from the EC2 instances via the Database Security Group.
6.  **Static Assets (S3 & CloudFront):**
    *   Application static assets (CSS, JS, images) are stored in a private S3 bucket.
    *   A CloudFront distribution serves these assets globally, accessing the S3 bucket via an Origin Access Identity (OAI) for security.
7.  **Networking (VPC):**
    *   Custom VPC with public and private subnets across multiple AZs.
    *   NAT Gateways in public subnets allow instances in private subnets to access the internet for updates/external APIs.
    *   Internet Gateway allows internet access for the ALB and NAT Gateways.

*(Suggestion: Include a diagram image here if possible)*

## Prerequisites

*   **AWS Account:** An AWS account with sufficient permissions to create the resources defined in `main.tf`.
*   **AWS Credentials:** Configured AWS credentials locally for Terraform execution (e.g., via environment variables `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, or an AWS credentials file).
*   **Terraform:** Terraform CLI installed (version ~> 1.4 recommended, check `required_version` if specified).
*   **Registered Domain Name:** A domain name registered with Route 53 or another registrar (required for ACM certificate validation and DNS records).
*   **Git:** Git installed for cloning the repository.
*   **(For CI/CD):**
    *   GitHub Repository.
    *   GitHub Secrets:
        *   `AWS_ACCESS_KEY_ID`: For GitHub Actions to authenticate with AWS.
        *   `AWS_SECRET_ACCESS_KEY`: For GitHub Actions to authenticate with AWS.
        *   `GITHUB_TOKEN`: Usually available automatically, needed for PR comments.
    *   GitHub Variables (Repository or Environment level):
        *   `AWS_REGION`: e.g., `us-east-1`
        *   `ASSETS_BUCKET_NAME`: The globally unique name for your S3 assets bucket (defined in `terraform.tfvars`).
        *   `CLOUDFRONT_DISTRIBUTION_ID`: **Note:** It's better practice to get this dynamically from Terraform output after apply, rather than storing as a static variable. The current `deploy.yml` may need adjustment.

## Project Structure
content_copy
download
Use code with caution.
Markdown
terraform-AWS-scalable-backend/
├── .github/
│ └── workflows/
│  └── deploy.yml # GitHub Actions workflow for CI/CD
├── app/
│ └── [your application code]
├── main.tf # Main Terraform configuration defining resources
├── variables.tf # Input variable definitions
├── terraform.tfvars # Variable values (Customize this!)
└── README.md # This file

## Configuration

1.  **Clone the repository:**
    ```bash
    git clone <your-repository-url>
    cd webapp-project
    ```
2.  **Customize Variables:**
    *   Rename `terraform.tfvars.example` to `terraform.tfvars` (if applicable) or edit the existing `terraform.tfvars`.
    *   Update the placeholder values in `terraform.tfvars` with your specific settings:
        *   `aws_region`
        *   `project_prefix` (used to name resources)
        *   `assets_bucket_name` (must be globally unique)
        *   `domain_name` (your registered domain)
        *   `db_name`
        *   `tags` (Environment, Project, Owner etc.)
    *   **Important:** For sensitive variables like `db_password` and `db_username`:
        *   **Do not commit them directly to `terraform.tfvars` in a real project.**
        *   Set them using environment variables (`export TF_VAR_db_password="yourpassword"`) before running Terraform.
        *   **Recommended:** Integrate with AWS Secrets Manager. Modify the Terraform code (`aws_db_instance`) to *not* accept these variables directly, and update the EC2 `user_data` script (and application code) to fetch secrets from Secrets Manager using the assigned EC2 IAM Role.

3.  **GitHub Actions Secrets/Variables:** Configure the required secrets and variables in your GitHub repository settings for the CI/CD pipeline (`deploy.yml`) to function.

## Usage / Deployment

### Manual Deployment (Local)

1.  **Initialize Terraform:**
    ```bash
    terraform init
    ```
2.  **Plan:** Review the infrastructure changes Terraform proposes.
    ```bash
    terraform plan -var-file=terraform.tfvars
    ```
3.  **Apply:** Create or update the infrastructure.
    ```bash
    terraform apply -var-file=terraform.tfvars
    # Or: terraform apply -var-file=terraform.tfvars -auto-approve (Use with caution)
    ```

### Automated Deployment (GitHub Actions)

*   **Pull Requests:** When a PR is opened against the `main` branch, the `deploy.yml` workflow will run `terraform init`, `validate`, and `plan`. The plan output will be posted as a comment on the PR for review.
*   **Merge to `main`:** When changes are pushed or merged to the `main` branch, the workflow will run `terraform init`, `validate`, and `apply -auto-approve` to deploy the infrastructure changes. It will then attempt to sync the `app/build` directory (assuming a frontend build process) to the S3 assets bucket and invalidate the CloudFront cache. **Note:** Backend deployment logic is missing here.

## Infrastructure Components Provisioned

*   **Networking:**
    *   `aws_vpc` (using `terraform-aws-modules/vpc/aws`)
    *   Public & Private Subnets across multiple AZs
    *   Internet Gateway
    *   NAT Gateways (one per AZ)
    *   Route Tables
*   **Security:**
    *   `aws_security_group` (ALB, Web Servers, Database)
    *   `aws_iam_role` (for EC2 instances)
    *   `aws_iam_policy` (custom policy for EC2 role)
    *   `aws_iam_instance_profile` (for EC2 instances)
    *   `aws_s3_bucket_policy` (for CloudFront access)
    *   `aws_s3_bucket_public_access_block`
*   **Load Balancing:**
    *   `aws_lb` (Application Load Balancer)
    *   `aws_lb_target_group`
    *   `aws_lb_listener` (HTTP redirect to HTTPS)
    *   `aws_lb_listener` (HTTPS listener)
*   **Compute:**
    *   `aws_launch_template` (includes IAM profile, user data placeholder)
    *   `aws_autoscaling_group`
    *   `aws_autoscaling_policy` (Scale Up/Down)
    *   `aws_cloudwatch_metric_alarm` (CPU High/Low for scaling)
*   **Database:**
    *   `aws_db_instance` (RDS MySQL, Multi-AZ)
    *   `aws_db_subnet_group`
*   **Storage & CDN:**
    *   `aws_s3_bucket` (for static assets)
    *   `aws_cloudfront_origin_access_identity`
    *   `aws_cloudfront_distribution`
*   **DNS & Certificates:**
    *   `aws_acm_certificate`
    *   `aws_route53_record` (for ACM validation)
    *   `aws_acm_certificate_validation`
    *   (Optional) `aws_route53_zone`
    *   `aws_route53_record` (A records for ALB - apex/www)

## Security Considerations

*   **HTTPS:** Enforced at the ALB level using ACM certificates.
*   **Least Privilege:** Security Groups restrict traffic between tiers. EC2 instances use an IAM role with specific permissions needed for AWS service interaction.
*   **Secrets Management:** Database credentials should ideally be managed via AWS Secrets Manager and fetched by the application using the EC2 IAM role (requires modification of `user_data`/application logic). Avoid storing sensitive data directly in Terraform state or variables files.
*   **Private Resources:** EC2 instances and the RDS database are placed in private subnets, inaccessible directly from the internet.
*   **S3 Security:** The assets bucket is private, only accessible via CloudFront OAI.

## Monitoring

*   Basic CloudWatch Alarms are configured for ASG CPU utilization to trigger scaling.
*   **TODO:** Enhance monitoring by:
    *   Installing and configuring the CloudWatch Agent on EC2 instances (via `user_data`) to collect detailed metrics (Memory, Disk) and logs (application, system).
    *   Creating CloudWatch Log Groups.
    *   Adding more CloudWatch Alarms (e.g., Memory, Disk, ALB 5xx errors, Target Group health, RDS metrics).
    *   Creating CloudWatch Dashboards or integrating with tools like Grafana.
