#!/usr/bin/env bash
#
# setup_tf_repo.sh
#
# Usage: ./setup_tf_repo.sh [folder_name]
# If [folder_name] is not provided, "my-resize-repo" will be used by default.

set -e

# Default folder name if none provided
REPO_NAME="${1:-my-resize-repo}"

# Create the top-level directory structure
mkdir -p "${REPO_NAME}"
mkdir -p "${REPO_NAME}/modules/ssm_automation/templates"
mkdir -p "${REPO_NAME}/scripts"

# Create a top-level main.tf calling the module (note the use of $REPO_NAME below)
cat > "${REPO_NAME}/main.tf" << EOF
terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}

# The AWS provider will read the profile and region variables from variables.tf
provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}

module "ssm_automation" {
  source               = "./modules/ssm_automation"
  document_name        = "${REPO_NAME}-ResizeInstanceAutomation"
  pre_downtime_script  = "pre_downtime_linux.sh"     # Change to "pre_downtime_windows.ps1" for Windows
  post_downtime_script = "post_downtime_linux.sh"    # Change to "post_downtime_windows.ps1" for Windows
}
EOF

# Create a top-level variables.tf with defaults for aws_profile and aws_region
cat > "${REPO_NAME}/variables.tf" << 'EOF'
variable "aws_profile" {
  type        = string
  description = "Which AWS CLI profile to use (Ex: admin-usergroup, prod, orig)."
  default     = "admin-usergroup"
}

variable "aws_region" {
  type        = string
  description = "Which AWS region to use (Ex: us-east-1, us-west-2)."
  default     = "us-east-1"
}

# You can place other root-level variables here if needed.
EOF

# Create a top-level README.md
cat > "${REPO_NAME}/README.md" << EOF
# ${REPO_NAME}

This repository contains Terraform code to create an AWS SSM Automation document for resizing EC2 instances with OS-specific pre- and post-downtime checks.

## Directory Structure

\`\`\`
${REPO_NAME}/
├── main.tf
├── variables.tf
├── README.md
├── modules
│   └── ssm_automation
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── templates
│           └── resize_template.yaml
└── scripts
    ├── pre_downtime_linux.sh
    ├── post_downtime_linux.sh
    ├── pre_downtime_windows.ps1
    └── post_downtime_windows.ps1
\`\`\`

## How It Works

- **main.tf**: Defines the AWS provider and calls the \`ssm_automation\` module.
- **variables.tf**: Lets you set \`aws_profile\` and \`aws_region\` to pick which account and region to deploy to.
- **modules/ssm_automation**: Contains Terraform files for creating the SSM Automation document.
- **scripts**: Contains OS-specific scripts:
  - **\`pre_downtime_linux.sh\`** / **\`post_downtime_linux.sh\`**
  - **\`pre_downtime_windows.ps1\`** / **\`post_downtime_windows.ps1\`**

The SSM Automation document references these scripts and picks the correct SSM Run Document (Shell or PowerShell) based on file extension.

## Quick Start

1. Install Terraform (v1.0.0 or higher).
2. \`cd\` into this directory (\`cd ${REPO_NAME}\`).
3. Run:
   \`\`\`
   terraform init
   terraform apply
   \`\`\`
   This deploys to the default profile (\`admin-usergroup\`) and the \`us-east-1\` region.

## Switching Accounts and Regions

To deploy to other accounts or regions, use the \`-var\` flag:

- **Different Profile** (Ex: \`prod\`):
  \`\`\`
  terraform apply -var="aws_profile=prod"
  \`\`\`
- **Different Region** (Ex: \`us-west-2\`):
  \`\`\`
  terraform apply -var="aws_region=us-west-2"
  \`\`\`
- **Both**:
  \`\`\`
  terraform apply -var="aws_profile=orig" -var="aws_region=us-west-1"
  \`\`\`

## Customizing Scripts

Inside \`scripts/\`, you can add your own commands to:
- **\`pre_downtime_linux.sh\`** or **\`post_downtime_linux.sh\`** (for Linux).
- **\`pre_downtime_windows.ps1\`** or **\`post_downtime_windows.ps1\`** (for Windows).

Update \`main.tf\` if you want to switch from Linux to Windows scripts by changing the \`pre_downtime_script\` or \`post_downtime_script\` variables in the module call.

## Next Steps

- Add more steps to the SSM Automation document if needed (for capacity reservations or advanced checks).
- Create more scripts for different OS tasks.
- Adjust the region, profile, or other variables for your environment.

EOF

# Create the ssm_automation module files
cat > "${REPO_NAME}/modules/ssm_automation/main.tf" << 'EOF'
resource "aws_ssm_document" "resize_instance" {
  name          = var.document_name
  document_type = "Automation"

  content = templatefile("${path.module}/templates/resize_template.yaml", {
    pre_downtime_script  = file("${path.module}/../scripts/${var.pre_downtime_script}")
    post_downtime_script = file("${path.module}/../scripts/${var.post_downtime_script}")
  })
}
EOF

cat > "${REPO_NAME}/modules/ssm_automation/variables.tf" << 'EOF'
variable "document_name" {
  type        = string
  description = "Name of the SSM Automation document."
}

variable "pre_downtime_script" {
  type        = string
  description = "Name of the pre-downtime script file to use (Ex: .sh or .ps1)."
}

variable "post_downtime_script" {
  type        = string
  description = "Name of the post-downtime script file to use (Ex: .sh or .ps1)."
}
EOF

cat > "${REPO_NAME}/modules/ssm_automation/outputs.tf" << 'EOF'
# If you want to output any values from this module, add them here.
# Ex: output "ssm_document_name" {
#   value = aws_ssm_document.resize_instance.name
# }
EOF

# Create placeholder scripts
cat > "${REPO_NAME}/scripts/pre_downtime_linux.sh" << 'EOF'
#!/usr/bin/env bash
echo "Performing Linux pre-downtime checks..."
# Add your custom checks here
EOF

cat > "${REPO_NAME}/scripts/post_downtime_linux.sh" << 'EOF'
#!/usr/bin/env bash
echo "Performing Linux post-downtime checks..."
# Add your custom checks here
EOF

cat > "${REPO_NAME}/scripts/pre_downtime_windows.ps1" << 'EOF'
Write-Host "Performing Windows pre-downtime checks..."
# Add your custom checks here
EOF

cat > "${REPO_NAME}/scripts/post_downtime_windows.ps1" << 'EOF'
Write-Host "Performing Windows post-downtime checks..."
# Add your custom checks here
EOF

# Create the template for the SSM Automation document.
cat > "${REPO_NAME}/modules/ssm_automation/templates/resize_template.yaml" << EOF
schemaVersion: '0.3'
description: "Resize an EC2 instance with OS-specific pre/post checks from ${REPO_NAME}"
parameters:
  InstanceId:
    type: String
    description: "ID of the instance to resize"
  TargetInstanceType:
    type: String
    description: "Target instance type"
  AutomationAssumeRole:
    type: String
    description: "Role ARN to assume for automation"
    default: ""
  RetryAttempts:
    type: String
    description: "Number of retry attempts for capacity reservation"
    default: "5"
  RetryIntervalSeconds:
    type: String
    description: "Interval between retry attempts in seconds"
    default: "30"
  AvailabilityZone:
    type: String
    description: "AZ where capacity reservation should be created"
  InstancePlatform:
    type: String
    description: "Platform for the capacity reservation (e.g., Linux/UNIX)"
    default: "Linux/UNIX"
  ReservationName:
    type: String
    description: "Name tag for the capacity reservation"

mainSteps:
  - name: GetInstanceDetails
    action: aws:executeAwsApi
    inputs:
      Service: ec2
      Api: DescribeInstances
      InstanceIds:
        - "{{ InstanceId }}"
    outputs:
      - Name: Platform
        Selector: "$.Reservations[0].Instances[0].Platform"
        Type: String
      - Name: AvailabilityZone
        Selector: "$.Reservations[0].Instances[0].Placement.AvailabilityZone"
        Type: String
      - Name: CurrentInstanceType
        Selector: "$.Reservations[0].Instances[0].InstanceType"
        Type: String
    description: "Get details about the instance to be resized"
    onFailure: "Abort"
    nextStep: "CreateCapacityReservation"

  - name: CreateCapacityReservation
    action: aws:executeScript
    inputs:
      Runtime: python3.9
      Handler: retry_handler
      Script: |
        import boto3
        import time
        import traceback
        import logging

        logger = logging.getLogger()
        logger.setLevel(logging.INFO)

        def retry_handler(events, context):
            ec2 = boto3.client('ec2')
            retries = int(events['RetryAttempts'])
            delay = int(events['RetryIntervalSeconds'])
            instance_type = events['InstanceType']
            az = events['AvailabilityZone']
            platform = events['InstancePlatform']
            reservation_name = events['ReservationName']

            for attempt in range(retries):
                try:
                    logger.info(f"Attempt {attempt + 1} to create Capacity Reservation...")
                    response = ec2.create_capacity_reservation(
                        InstanceType=instance_type,
                        InstancePlatform=platform,
                        AvailabilityZone=az,
                        InstanceCount=1,
                        Tenancy="default",
                        TagSpecifications=[
                            {
                                'ResourceType': 'capacity-reservation',
                                'Tags': [{'Key': 'Name', 'Value': reservation_name}]
                            }
                        ]
                    )
                    logger.info("Capacity Reservation Created: %s", response['CapacityReservation']['CapacityReservationId'])
                    return {"Success": True, "CapacityReservationId": response['CapacityReservation']['CapacityReservationId']}
                except Exception as e:
                    if "InsufficientCapacity" in str(e):
                        logger.warning(f"Capacity unavailable. Retrying in {delay} seconds...")
                        time.sleep(delay)
                    else:
                        logger.error("Critical error: %s", str(e))
                        traceback.print_exc()
                        return {"Success": False, "Error": str(e)}

            logger.error("All retry attempts failed. Capacity Reservation could not be created.")
            return {"Success": False, "Error": "Insufficient capacity after all retries."}

      InputPayload:
        RetryAttempts: "{{ RetryAttempts }}"
        RetryIntervalSeconds: "{{ RetryIntervalSeconds }}"
        InstanceType: "{{ TargetInstanceType }}"
        AvailabilityZone: "{{ AvailabilityZone }}"
        InstancePlatform: "{{ InstancePlatform }}"
        ReservationName: "{{ ReservationName }}"
    description: "Create a Capacity Reservation with retry logic for insufficient capacity"

  - name: VerifyCapacityReservation
    action: aws:assertAwsResourceProperty
    inputs:
      Service: "ec2"
      Api: "create_capacity_reservation"
      PropertySelector: "$.Success"
      DesiredValues:
        - "True"
    description: "Verify that the Capacity Reservation was successfully created"
    onFailure: "Abort"
    nextStep: "PreDowntimeChecks"

  - name: PreDowntimeChecks
    action: aws:runCommand
    inputs:
      DocumentName: '{{ if contains ".ps1" .pre_downtime_script }}AWS-RunPowerShellScript{{ else }}AWS-RunShellScript{{ end }}'
      InstanceIds:
        - "{{ InstanceId }}"
      Parameters:
        commands:
          - |
            ${pre_downtime_script}

  - name: StopInstance
    action: aws:executeAwsApi
    inputs:
      Service: ec2
      Api: StopInstances
      InstanceIds:
        - "{{ InstanceId }}"

  - name: WaitForInstanceStopped
    action: aws:waitForAwsResourceProperty
    inputs:
      Service: ec2
      Api: DescribeInstances
      InstanceIds:
        - "{{ InstanceId }}"
      PropertySelector: "$.Reservations[0].Instances[0].State.Name"
      DesiredValues:
        - stopped
    timeoutSeconds: 600

  - name: ModifyInstanceType
    action: aws:executeAwsApi
    inputs:
      Service: ec2
      Api: ModifyInstanceAttribute
      InstanceId: "{{ InstanceId }}"
      InstanceType:
        Value: "{{ TargetInstanceType }}"

  - name: StartInstance
    action: aws:executeAwsApi
    inputs:
      Service: ec2
      Api: StartInstances
      InstanceIds:
        - "{{ InstanceId }}"

  - name: WaitForInstanceRunning
    action: aws:waitForAwsResourceProperty
    inputs:
      Service: ec2
      Api: DescribeInstances
      InstanceIds:
        - "{{ InstanceId }}"
      PropertySelector: "$.Reservations[0].Instances[0].State.Name"
      DesiredValues:
        - running
    timeoutSeconds: 600

  - name: PostDowntimeChecks
    action: aws:runCommand
    inputs:
      DocumentName: '{{ if contains ".ps1" .post_downtime_script }}AWS-RunPowerShellScript{{ else }}AWS-RunShellScript{{ end }}'
      InstanceIds:
        - "{{ InstanceId }}"
      Parameters:
        commands:
          - |
            ${post_downtime_script}
EOF

echo "Terraform repo created in ./${REPO_NAME}"
echo "You can edit scripts under ./${REPO_NAME}/scripts/, then run 'terraform init && terraform apply' within ./${REPO_NAME}."
echo "To switch accounts/regions, use -var=\"aws_profile=XYZ\" -var=\"aws_region=us-west-2\" during apply."