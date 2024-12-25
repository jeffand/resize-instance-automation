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
mkdir -p "${REPO_NAME}-iam"

# Create IAM role configuration
cat > "${REPO_NAME}-iam/main.tf" << 'EOF'
provider "aws" {
  region  = var.aws_region
  profile = "admin-usergroup"
}

resource "aws_iam_role" "automation_role" {
  name = "${var.name_prefix}-automation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "automation_policy" {
  name = "${var.name_prefix}-automation-policy"
  role = aws_iam_role.automation_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateCapacityReservation",
          "ec2:DescribeCapacityReservations",
          "ec2:TagResource",
          "ec2:CreateTags",
          "ec2:DescribeInstances",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:ModifyInstanceAttribute",
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:DescribeInstanceInformation",
          "ssm:GetAutomationExecution",
          "ssm:StartAutomationExecution",
          "ssm:StopAutomationExecution",
          "ssm:ListCommands",
          "ssm:ListCommandInvocations",
          "sts:AssumeRole"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.automation_role.arn
      }
    ]
  })
}

output "automation_role_arn" {
  description = "ARN of the IAM role for SSM automation"
  value       = aws_iam_role.automation_role.arn
}
EOF

cat > "${REPO_NAME}-iam/variables.tf" << 'EOF'
variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1" # Change this to your preferred region
}

variable "name_prefix" {
  type        = string
  description = "Prefix to use for IAM role and policy names"
  default     = "resize-automation"
}
EOF

cat > "${REPO_NAME}-iam/versions.tf" << 'EOF'
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
EOF

cat > "${REPO_NAME}-iam/terraform.tfvars" << 'EOF'
aws_region  = "us-east-1" # Change this to your preferred region
name_prefix = "resize-automation"
EOF

# Create README for IAM module
cat > "${REPO_NAME}-iam/README.md" << EOF
# ${REPO_NAME}-iam

This module creates the IAM role and policy required for the EC2 resize automation. The role is assumed by AWS Systems Manager (SSM) to perform instance resize operations.

## Directory Structure

\`\`\`
${REPO_NAME}-iam/
├── main.tf          # IAM role and policy definitions
├── variables.tf     # Variable declarations
├── versions.tf      # Provider and terraform version constraints
├── terraform.tfvars # Default variable values
└── README.md       # This file
\`\`\`

## IAM Role Details

The module creates:
1. An IAM role that can be assumed by the SSM service
2. An IAM policy attached to this role with permissions for:
   - EC2 operations (stop, start, modify, describe instances)
   - Capacity reservation management
   - SSM automation and command execution
   - Tag management

### Permissions Breakdown

The role has permissions for:
- \`ec2:CreateCapacityReservation\` - Create capacity reservations for new instance sizes
- \`ec2:DescribeCapacityReservations\` - Check reservation status
- \`ec2:TagResource\` & \`ec2:CreateTags\` - Tag resources during automation
- \`ec2:DescribeInstances\` - Get instance details
- \`ec2:StopInstances\` & \`ec2:StartInstances\` - Stop/start instances for resizing
- \`ec2:ModifyInstanceAttribute\` - Change instance type
- \`ssm:SendCommand\` & \`ssm:GetCommandInvocation\` - Run pre/post checks
- \`ssm:DescribeInstanceInformation\` - Get SSM instance details
- \`ssm:*Automation*\` - Execute and manage automations
- \`sts:AssumeRole\` - Allow role assumption

## Quick Start

1. Navigate to this directory:
   \`\`\`bash
   cd ${REPO_NAME}-iam
   \`\`\`

2. Initialize and apply:
   \`\`\`bash
   terraform init
   terraform apply
   \`\`\`

3. Note the role ARN in the output - you'll need this when running the resize automation.

## Configuration

### Required Variables
None - all variables have defaults

### Optional Variables
- \`aws_region\` (default: "us-east-1"): AWS region to deploy to
- \`name_prefix\` (default: "resize-automation"): Prefix for IAM role and policy names

### Outputs
- \`automation_role_arn\`: ARN of the created IAM role

## Security Considerations

The IAM role follows the principle of least privilege, but does require broad EC2 and SSM permissions to function. The role:
1. Can only be assumed by the SSM service
2. Has permissions scoped to EC2 and SSM operations
3. Includes only permissions necessary for the resize automation

## Usage in Automation

The role ARN should be passed to the SSM automation document as the \`AutomationAssumeRole\` parameter. The automation will then use this role to:
1. Query instance details
2. Manage capacity reservations
3. Stop and start instances
4. Run pre/post-resize checks

EOF

# Create a top-level main.tf calling the module
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

# Create module main.tf with updated SSM document
cat > "${REPO_NAME}/modules/ssm_automation/main.tf" << 'EOF'
resource "aws_ssm_document" "resize_instance" {
  name            = var.document_name
  document_type   = "Automation"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "0.3"
    description   = "Resize an EC2 instance with OS-specific pre/post checks from my-resize-repo"
    parameters = {
      InstanceId = {
        type        = "String"
        description = "ID of the instance to resize"
      }
      TargetInstanceType = {
        type        = "String"
        description = "Target instance type"
      }
      AutomationAssumeRole = {
        type        = "String"
        description = "Role ARN to assume for automation"
        default     = ""
      }
      StopTimeoutSeconds = {
        type        = "String"
        description = "Maximum time to wait for instance to stop (in seconds)"
        default     = "600"
      }
      StartTimeoutSeconds = {
        type        = "String"
        description = "Maximum time to wait for instance to start (in seconds)"
        default     = "600"
      }
      RetryAttempts = {
        type        = "String"
        description = "Number of retry attempts for capacity reservation"
        default     = "5"
      }
      RetryIntervalSeconds = {
        type        = "String"
        description = "Interval between retry attempts in seconds"
        default     = "30"
      }
      InstancePlatform = {
        type        = "String"
        description = "Platform for the capacity reservation (e.g., Linux/UNIX)"
        default     = "Linux/UNIX"
      }
      ReservationName = {
        type        = "String"
        description = "Name tag for the capacity reservation"
      }
    }
    mainSteps = [
      {
        name        = "GetInstanceDetails"
        action      = "aws:executeAwsApi"
        inputs = {
          Service = "ec2"
          Api = "DescribeInstances"
          InstanceIds = ["{{ InstanceId }}"]
        }
        outputs = [
          {
            Name = "Platform"
            Selector = "$.Reservations[0].Instances[0].Platform"
            Type = "String"
          },
          {
            Name = "AvailabilityZone"
            Selector = "$.Reservations[0].Instances[0].Placement.AvailabilityZone"
            Type = "String"
          },
          {
            Name = "CurrentInstanceType"
            Selector = "$.Reservations[0].Instances[0].InstanceType"
            Type = "String"
          }
        ]
        description = "Get details about the instance to be resized"
        onFailure = "Abort"
        nextStep = "CreateCapacityReservation"
      },
      {
        name = "CreateCapacityReservation"
        action = "aws:executeScript"
        inputs = {
          Runtime = "python3.9"
          Handler = "retry_handler"
          Script = <<-EOT
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
            reservation_id = response['CapacityReservation']['CapacityReservationId']
            logger.info("Capacity Reservation Created: %s", reservation_id)
            return {
                "CapacityReservationId": reservation_id,
                "Success": True
            }
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
EOT
        }
        outputs = [
          {
            Name = "CapacityReservationId"
            Selector = "$.Payload.CapacityReservationId"
            Type = "String"
          },
          {
            Name = "Success"
            Selector = "$.Payload.Success"
            Type = "Boolean"
          }
        ]
        description = "Create a Capacity Reservation with retry logic for insufficient capacity"
        onFailure = "Abort"
        nextStep = "VerifyCapacityReservation"
      },
      {
        name = "VerifyCapacityReservation"
        action = "aws:waitForAwsResourceProperty"
        inputs = {
          Service = "ec2"
          Api = "DescribeCapacityReservations"
          CapacityReservationIds = ["{{ CreateCapacityReservation.CapacityReservationId }}"]
          PropertySelector = "$.CapacityReservations[0].State"
          DesiredValues = ["active"]
        }
        timeoutSeconds = 30
        description = "Verify that the Capacity Reservation is active"
        onFailure = "Abort"
        nextStep = "PreDowntimeChecks"
      },
      {
        name = "PreDowntimeChecks"
        description = "Run pre-downtime checks on the instance"
        action = "aws:runCommand"
        inputs = {
          DocumentName = "AWS-RunShellScript"
          InstanceIds = ["{{ InstanceId }}"]
          Parameters = {
            commands = ["${pre_downtime_script}"]
          }
        }
        onFailure = "Continue"
        nextStep = "StopInstance"
      },
      {
        name = "StopInstance"
        action = "aws:executeAwsApi"
        inputs = {
          Service = "ec2"
          Api = "StopInstances"
          InstanceIds = ["{{ InstanceId }}"]
        }
      },
      {
        name = "WaitForInstanceStopped"
        action = "aws:waitForAwsResourceProperty"
        inputs = {
          Service = "ec2"
          Api = "DescribeInstances"
          InstanceIds = ["{{ InstanceId }}"]
          PropertySelector = "$.Reservations[0].Instances[0].State.Name"
          DesiredValues = ["stopped"]
        }
        timeoutSeconds = "{{ StopTimeoutSeconds }}"
      },
      {
        name = "ModifyInstanceType"
        action = "aws:executeAwsApi"
        inputs = {
          Service = "ec2"
          Api = "ModifyInstanceAttribute"
          InstanceId = "{{ InstanceId }}"
          InstanceType = {
            Value = "{{ TargetInstanceType }}"
          }
        }
      },
      {
        name = "StartInstance"
        action = "aws:executeAwsApi"
        inputs = {
          Service = "ec2"
          Api = "StartInstances"
          InstanceIds = ["{{ InstanceId }}"]
        }
      },
      {
        name = "WaitForInstanceRunning"
        action = "aws:waitForAwsResourceProperty"
        inputs = {
          Service = "ec2"
          Api = "DescribeInstances"
          InstanceIds = ["{{ InstanceId }}"]
          PropertySelector = "$.Reservations[0].Instances[0].State.Name"
          DesiredValues = ["running"]
        }
        timeoutSeconds = "{{ StartTimeoutSeconds }}"
      },
      {
        name = "PostDowntimeChecks"
        description = "Run post-downtime checks on the instance"
        action = "aws:runCommand"
        inputs = {
          DocumentName = "AWS-RunShellScript"
          InstanceIds = ["{{ InstanceId }}"]
          Parameters = {
            commands = ["${post_downtime_script}"]
          }
        }
      },
      {
        name = "DeleteCapacityReservation"
        action = "aws:executeAwsApi"
        inputs = {
          Service = "ec2"
          Api = "CancelCapacityReservation"
          CapacityReservationId = "{{ CreateCapacityReservation.CapacityReservationId }}"
        }
        onFailure = "Continue"
        description = "Delete the Capacity Reservation to clean up resources."
      },
      {
        name = "EndAutomation"
        action = "aws:executeScript"
        inputs = {
          Runtime = "python3.8"
          Handler = "main"
          Script = <<-EOT
def main(event):
    return "Automation completed successfully."
EOT
        }
        isEnd = true
        description = "Mark the end of the automation process."
      }
    ]
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

# Create script files
mkdir -p "${REPO_NAME}/scripts"

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

# Make Linux scripts executable
chmod +x "${REPO_NAME}/scripts/pre_downtime_linux.sh"
chmod +x "${REPO_NAME}/scripts/post_downtime_linux.sh"

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
  \`\`\`bash
  terraform apply -var="aws_profile=prod"
  \`\`\`
- **Different Region** (Ex: \`us-west-2\`):
  \`\`\`bash
  terraform apply -var="aws_region=us-west-2"
  \`\`\`
- **Both**:
  \`\`\`bash
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

### Resize Automation Steps

The SSM Automation document executes the following steps in order:

1. **Get Instance Details**: 
   - Retrieves information about the target instance
   - Captures platform type, availability zone, and current instance type
   - Aborts if instance not found

2. **Create Capacity Reservation**:
   - Attempts to reserve capacity for the target instance type
   - Implements retry logic for handling insufficient capacity
   - Retries up to 5 times with 30-second intervals

3. **Verify Capacity Reservation**:
   - Confirms successful capacity reservation
   - Checks the Success property of the reservation creation
   - Aborts if verification fails
   - Ensures capacity is available before proceeding

4. **Pre-Downtime Checks**:
   - Runs OS-specific validation scripts
   - Uses PowerShell for Windows or Shell for Linux based on file extension

5. **Stop Instance**:
   - Gracefully stops the EC2 instance
   - Waits up to 10 minutes for complete shutdown

6. **Modify Instance**:
   - Changes the instance type to the target size

7. **Start Instance**:
   - Starts the resized instance
   - Waits up to 10 minutes for instance to be running

8. **Post-Downtime Checks**:
   - Runs OS-specific validation scripts
   - Verifies instance is working correctly after resize

9. **Cleanup**:
   - Removes the capacity reservation
   - Continues automation even if cleanup fails

10. **Completion**:
    - Marks the automation as complete
    - Returns success message

The automation uses native AWS SSM Run Commands to execute scripts, making it compatible with both Windows and Linux instances without requiring additional configuration.

## Automation Parameters

The SSM Automation accepts the following parameters:

### Required Parameters
- **InstanceId**: ID of the EC2 instance to resize
- **TargetInstanceType**: The desired instance type (e.g., t3.large)

### Optional Parameters with Defaults
- **RetryAttempts**: Number of capacity reservation retry attempts (Default: 5)
- **RetryIntervalSeconds**: Seconds between retry attempts (Default: 30)
- **InstancePlatform**: Platform for capacity reservation (Default: Linux/UNIX)
- **AutomationAssumeRole**: Role ARN for automation (Default: empty)
- **ReservationName**: Name tag for capacity reservation

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
      AssumeRole: "{{ AutomationAssumeRole }}"
      InputPayload:
        RetryAttempts         = "{{ RetryAttempts }}"
        RetryIntervalSeconds  = "{{ RetryIntervalSeconds }}"
        TargetInstanceType    = "{{ TargetInstanceType }}"
        AvailabilityZone      = "{{ GetInstanceDetails.AvailabilityZone }}"
        InstancePlatform      = "{{ InstancePlatform }}"
        ReservationName       = "{{ ReservationName }}"
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
            instance_type = events['TargetInstanceType']
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
                    reservation_id = response['CapacityReservation']['CapacityReservationId']
                    logger.info("Capacity Reservation Created: %s", reservation_id)
                    return {
                        "CapacityReservationId": reservation_id,
                        "Success": True
                    }
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
    outputs:
      - Name: CapacityReservationId
        Selector: "$.Payload.CapacityReservationId"
        Type: String
      - Name: Success
        Selector: "$.Payload.Success"
        Type: Boolean
    description: "Create a Capacity Reservation with retry logic for insufficient capacity"
    onFailure: "Abort"
    nextStep: "VerifyCapacityReservation"

  - name: VerifyCapacityReservation
    action: aws:waitForAwsResourceProperty
    inputs:
      Service: ec2
      Api: DescribeCapacityReservations
      CapacityReservationIds:
        - "{{ CreateCapacityReservation.CapacityReservationId }}"
      PropertySelector: "$.CapacityReservations[0].State"
      DesiredValues:
        - "active"
    timeoutSeconds: 30
    description: "Verify that the Capacity Reservation is active"
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
            \${pre_downtime_script}

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
    timeoutSeconds: "{{ StopTimeoutSeconds }}"

  - name: ModifyInstanceType
    action: aws:executeAwsApi
    inputs:
      Service: ec2
      Api: ModifyInstanceAttribute
      InstanceId: "{{ InstanceId }}"
      Attribute  = "instanceType"
      Value      = "{{ TargetInstanceType }}"
    description: "Change the instance type to the target size"

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
    timeoutSeconds: "{{ StartTimeoutSeconds }}"

  - name: PostDowntimeChecks
    action: aws:runCommand
    inputs:
      DocumentName: '{{ if contains ".ps1" .post_downtime_script }}AWS-RunPowerShellScript{{ else }}AWS-RunShellScript{{ end }}'
      InstanceIds:
        - "{{ InstanceId }}"
      Parameters:
        commands:
          - |
            \${post_downtime_script}

  - name: DeleteCapacityReservation
    action: aws:executeAwsApi
    inputs:
      Service: ec2
      Api: CancelCapacityReservation
      CapacityReservationId: "{{ CreateCapacityReservation.CapacityReservationId }}"
    onFailure: Continue
    description: "Delete the Capacity Reservation to clean up resources."

  - name: EndAutomation
    action: aws:executeScript
    inputs:
      Runtime: python3.8
      Handler: main
      Script: |
        def main(event):
            return "Automation completed successfully."
    isEnd: true
    description: "Mark the end of the automation process."
EOF

echo "Terraform repo created in ./${REPO_NAME} and ./${REPO_NAME}-iam"
echo "First, deploy the IAM role:"
echo "1. cd ./${REPO_NAME}-iam"
echo "2. terraform init && terraform apply"
echo ""
echo "Then, deploy the SSM automation:"
echo "1. cd ../${REPO_NAME}"
echo "2. terraform init && terraform apply"
echo ""
echo "To switch accounts/regions, use -var=\"aws_profile=XYZ\" -var=\"aws_region=us-west-2\" during apply."