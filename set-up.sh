#!/bin/bash
#******************************************************************************
#    AWS VPC Creation Shell Script
#******************************************************************************
#
# SYNOPSIS
#    Automates the creation of a custom IPv4 VPC, having both a public and a
#    private subnet, and a NAT gateway.
#
# DESCRIPTION
#    This shell script leverages the AWS Command Line Interface (AWS CLI) to
#    automatically create a custom VPC.  The script assumes the AWS CLI is
#    installed and configured with the necessary security credentials.
#
#==============================================================================
#
# NOTES
#   VERSION:   0.1.0
#   LASTEDIT:  03/18/2017
#   AUTHOR:    Joe Arauzo
#   EMAIL:     joe@arauzo.net
#   REVISIONS:
#       0.1.0  03/18/2017 - first release
#       0.0.1  02/25/2017 - work in progress
#
#==============================================================================
# TODO Check this out - looks useful. 
# https://aws.amazon.com/blogs/containers/developers-guide-to-using-amazon-efs-with-amazon-ecs-and-aws-fargate-part-3/
#
#==============================================================================
#
#   MODIFY THE SETTINGS BELOW
#==============================================================================
#
AWS_REGION="ap-southeast-1"
VPC_NAME="Sample ECS VPC"
VPC_CIDR="10.0.0.0/16"
SUBNET_PUBLIC_CIDR="10.0.0.0/24"
SUBNET_PUBLIC_AZ="ap-southeast-1a"
SUBNET_PUBLIC_NAME="10.0.0.0 - ap-southeast-1a"
SUBNET_PRIVATE_CIDR="10.0.1.0/24"
SUBNET_PRIVATE_AZ="ap-southeast-1b"
SUBNET_PRIVATE_NAME="10.0.1.0 - ap-southeast-1b"
CHECK_FREQUENCY=5
CLUSTER_NAME="ecs-cluster"
ECS_SG_NAME="ecs-sg"
EC2_SG_NAME="ec2-sg"
EFS_SG_NAME="efs-sg"
#
#==============================================================================
#   DO NOT MODIFY CODE BELOW
#==============================================================================
#
# Create VPC
echo "Creating VPC in preferred region..."
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block $VPC_CIDR \
  --query 'Vpc.{VpcId:VpcId}' \
  --output text \
  --region $AWS_REGION)
echo "  VPC ID '$VPC_ID' CREATED in '$AWS_REGION' region."

# Add Name tag to VPC
aws ec2 create-tags \
  --resources $VPC_ID \
  --tags "Key=Name,Value=$VPC_NAME" \
  --region $AWS_REGION
echo "  VPC ID '$VPC_ID' NAMED as '$VPC_NAME'."

# Create Public Subnet
echo "Creating Public Subnet..."
SUBNET_PUBLIC_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $SUBNET_PUBLIC_CIDR \
  --availability-zone $SUBNET_PUBLIC_AZ \
  --query 'Subnet.{SubnetId:SubnetId}' \
  --output text \
  --region $AWS_REGION)
echo "  Subnet ID '$SUBNET_PUBLIC_ID' CREATED in '$SUBNET_PUBLIC_AZ'" \
  "Availability Zone."

# Add Name tag to Public Subnet
aws ec2 create-tags \
  --resources $SUBNET_PUBLIC_ID \
  --tags "Key=Name,Value=$SUBNET_PUBLIC_NAME" \
  --region $AWS_REGION
echo "  Subnet ID '$SUBNET_PUBLIC_ID' NAMED as" \
  "'$SUBNET_PUBLIC_NAME'."

# Create Private Subnet
echo "Creating Private Subnet..."
SUBNET_PRIVATE_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block $SUBNET_PRIVATE_CIDR \
  --availability-zone $SUBNET_PRIVATE_AZ \
  --query 'Subnet.{SubnetId:SubnetId}' \
  --output text \
  --region $AWS_REGION)
echo "  Subnet ID '$SUBNET_PRIVATE_ID' CREATED in '$SUBNET_PRIVATE_AZ'" \
  "Availability Zone."

# Add Name tag to Private Subnet
aws ec2 create-tags \
  --resources $SUBNET_PRIVATE_ID \
  --tags "Key=Name,Value=$SUBNET_PRIVATE_NAME" \
  --region $AWS_REGION
echo "  Subnet ID '$SUBNET_PRIVATE_ID' NAMED as '$SUBNET_PRIVATE_NAME'."

# Create Internet gateway
echo "Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
  --query 'InternetGateway.{InternetGatewayId:InternetGatewayId}' \
  --output text \
  --region $AWS_REGION)
echo "  Internet Gateway ID '$IGW_ID' CREATED."

# Attach Internet gateway to your VPC
aws ec2 attach-internet-gateway \
  --vpc-id $VPC_ID \
  --internet-gateway-id $IGW_ID \
  --region $AWS_REGION
echo "  Internet Gateway ID '$IGW_ID' ATTACHED to VPC ID '$VPC_ID'."

# Create Route Table
echo "Creating Route Table..."
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --query 'RouteTable.{RouteTableId:RouteTableId}' \
  --output text \
  --region $AWS_REGION)
echo "  Route Table ID '$ROUTE_TABLE_ID' CREATED."

# Create route to Internet Gateway
RESULT=$(aws ec2 create-route \
  --route-table-id $ROUTE_TABLE_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID \
  --region $AWS_REGION)
echo "  Route to '0.0.0.0/0' via Internet Gateway ID '$IGW_ID' ADDED to" \
  "Route Table ID '$ROUTE_TABLE_ID'."

# Associate Public Subnet with Route Table
RESULT=$(aws ec2 associate-route-table  \
  --subnet-id $SUBNET_PUBLIC_ID \
  --route-table-id $ROUTE_TABLE_ID \
  --region $AWS_REGION)
echo "  Public Subnet ID '$SUBNET_PUBLIC_ID' ASSOCIATED with Route Table ID" \
  "'$ROUTE_TABLE_ID'."

# Enable Auto-assign Public IP on Public Subnet
aws ec2 modify-subnet-attribute \
  --subnet-id $SUBNET_PUBLIC_ID \
  --map-public-ip-on-launch \
  --region $AWS_REGION
echo "  'Auto-assign Public IP' ENABLED on Public Subnet ID" \
  "'$SUBNET_PUBLIC_ID'."

# Create security group for the ECS Service
echo "Creating security group for ECS Service..."
ECS_SG_ID=$(aws ec2 create-security-group \
  --group-name $ECS_SG_NAME \
  --description "Security group for HTTP access" \
  --vpc-id $VPC_ID \
  --output text)
echo "  Security Group '$ECS_SG_ID' CREATED."

# Allow inbound HTTP traffic to the ECS security group.
echo "Authorizing inbound HTTP traffic on port 8080 to $ECS_SG_NAME..."
RESULT=$(aws ec2 authorize-security-group-ingress \
  --group-id $ECS_SG_ID \
  --protocol tcp --port 8080 --cidr 0.0.0.0/0 \
  --query 'Return' --output text)
echo "  Security Group '$ECS_SG_NAME' authorirised for inbound HTTP traffic: $RESULT."

# Create security group for the EC2 instance
echo "Creating security group for SSH access to EC2 instance..."
EC2_SG_ID=$(aws ec2 create-security-group \
  --group-name $EC2_SG_NAME \
  --description "Security group for SSH access" \
  --vpc-id $VPC_ID \
  --output text)
echo "  Security Group '$EC2_SG_ID' CREATED."

# Allow inbound SSH traffic to the EC2 security group.
echo "Authorizing inbound SSH traffic to $EC2_SG_NAME..."
RESULT=$(aws ec2 authorize-security-group-ingress \
  --group-id $EC2_SG_ID \
  --protocol tcp --port 22 --cidr 0.0.0.0/0 \
  --query 'Return' --output text)
echo "  Security Group '$EC2_SG_NAME' authorirised for inbound SSH traffic: $RESULT."

# Create a security group for the EFS mount target
echo "Creating security group for EFS mount target..."
EFS_SG_ID=$(aws ec2 create-security-group \
  --group-name $EFS_SG_NAME \
  --description "Security group for EFS mount target" \
  --vpc-id $VPC_ID \
  --output text)
echo "  Security Group '$EFS_SG_ID' CREATED."

# Allow access to the EFS mount target from the ECS security group
echo "Authorizing inbound EFS traffic to $EFS_SG_NAME..."
RESULT=$(aws ec2 authorize-security-group-ingress \
  --group-id $EFS_SG_ID \
  --protocol tcp --port 2049 \
  --source-group $ECS_SG_ID \
  --query 'Return' --output text)
echo "  Security Group '$ECS_SG_ID' authorirised for Amazon EFS mount target: $RESULT."

# Allow access to the EFS mount target from the EC2 security group
echo "Authorizing inbound EFS traffic to $EFS_SG_NAME..."
RESULT=$(aws ec2 authorize-security-group-ingress \
  --group-id $EFS_SG_ID \
  --protocol tcp --port 2049 \
  --source-group $EC2_SG_ID \
  --query 'Return' --output text)
echo "  Security Group '$EC2_SG_ID' authorirised for Amazon EFS mount target: $RESULT."

# Create an Amazon EFS file system
echo "Creating EFS file system..."
EFS_ID=$(aws efs create-file-system \
  --encrypted \
  --creation-token efs-for-ecs \
  --region ap-southeast-1 \
  --query 'FileSystemId' --output text)
echo "  Amazon EFS file system '$EFS_ID' CREATED."

# TODO
#aws efs put-lifecycle-configuration \
#--file-system-id fs-c657c8bf \
#--lifecycle-policies TransitionToIA=AFTER_30_DAYS \
#--region us-west-2

FORMATTED_MSG="Creating EFS file system ID '$EFS_ID' and waiting for it to "
FORMATTED_MSG+="become available.\n    Please BE PATIENT as this can take some "
FORMATTED_MSG+="time to complete.\n    ......\n"
printf "  $FORMATTED_MSG"
FORMATTED_MSG="STATUS: %s  -  %02dh:%02dm:%02ds elapsed while waiting for EFS file system "
FORMATTED_MSG+="to become available..."
SECONDS=0
LAST_CHECK=0
STATE='PENDING'
until [[ $STATE == 'AVAILABLE' ]]; do
  INTERVAL=$SECONDS-$LAST_CHECK
  if [[ $INTERVAL -ge $CHECK_FREQUENCY ]]; then
    STATE=$(aws efs describe-file-systems --file-system-id $EFS_ID \
      --query 'FileSystems[*].LifeCycleState' --output text)
    STATE=$(echo $STATE | tr '[:lower:]' '[:upper:]')
    LAST_CHECK=$SECONDS
  fi
  SECS=$SECONDS
  STATUS_MSG=$(printf "$FORMATTED_MSG" \
    $STATE $(($SECS/3600)) $(($SECS%3600/60)) $(($SECS%60)))
  printf "    $STATUS_MSG\033[0K\r"
  sleep 1
done
printf "\n    ......\n  EFS file system ID '$EFS_ID' is now AVAILABLE.\n"

# Create mount targets
echo "Creating mount targets..."
MOUNT_ID=$(aws efs create-mount-target \
--file-system-id $EFS_ID \
--subnet-id  $SUBNET_PUBLIC_ID \
--security-group $EFS_SG_ID \
--region ap-southeast-1 \
--query 'MountTargetId' --output text)
echo "  Mount target '$MOUNT_ID' for subnet '$SUBNET_PUBLIC_ID' CREATED."

MOUNT_ID=$(aws efs create-mount-target \
--file-system-id $EFS_ID \
--subnet-id  $SUBNET_PRIVATE_ID \
--security-group $EFS_SG_ID \
--region ap-southeast-1 \
--query 'MountTargetId' --output text)
echo "  Mount target '$MOUNT_ID' for subnet '$SUBNET_PRIVATE_ID' CREATED."

# Add content to the Amazon EFS file system
# TODO launch EC2 with EFS mounted -- include a script to create a file on the mount.
# Manual steps:
# ssh -i "MyKeyPair.pem" ec2-user@public-ip
# mkdir ~/efs-mount-point 
# sudo mount -t nfs -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport mount-target-DNS:/   ~/efs-mount-point  
# or
# sudo mount -t nfs -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport mount-target-ip:/  ~/efs-mount-point
# cd ~/efs-mount-point  
# sudo chmod go+rw .
# touch test-file.txt 

# Lauch an EC2 instance
echo "Launching EC2 instance..."
EC2_ID=$(aws ec2 run-instances --image-id ami-082105f875acab993 \
  --count 1 --instance-type t2.micro --key-name MyKeyPair \
  --security-group-ids $EC2_SG_ID --subnet-id $SUBNET_PUBLIC_ID \
  --query 'Instances[*].InstanceId' --output text)

FORMATTED_MSG="Launching EC2 instance ID '$EC2_ID' and waiting for it to "
FORMATTED_MSG+="become available.\n    Please BE PATIENT as this can take some "
FORMATTED_MSG+="time to complete.\n    ......\n"
printf "  $FORMATTED_MSG"
FORMATTED_MSG="STATUS: %s  -  %02dh:%02dm:%02ds elapsed while waiting for EC2 "
FORMATTED_MSG+="instance to become available..."
SECONDS=0
LAST_CHECK=0
STATE='PENDING'
until [[ $STATE == 'RUNNING' ]]; do
  INTERVAL=$SECONDS-$LAST_CHECK
  if [[ $INTERVAL -ge $CHECK_FREQUENCY ]]; then
    STATE=$(aws ec2 describe-instances --instance-id $EC2_ID \
      --query 'Reservations[*].Instances[*].State.Name' --output text)
    STATE=$(echo $STATE | tr '[:lower:]' '[:upper:]')
    LAST_CHECK=$SECONDS
  fi
  SECS=$SECONDS
  STATUS_MSG=$(printf "$FORMATTED_MSG" \
    $STATE $(($SECS/3600)) $(($SECS%3600/60)) $(($SECS%60)))
  printf "    $STATUS_MSG\033[0K\r"
  sleep 1
done
printf "\n    ......\n  EC2 Instance ID '$EC2_ID' is now RUNNING.\n"

# Step 5: Create a task definition
echo "Creating task defintion..."
sed ''s/dummy/$EFS_ID/'' aws-task-definition.json > temp.json
TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json file://temp.json \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)
echo "  Task Definition Arn '$TASK_DEF_ARN' REGISTERED."
rm temp.json

# TODO build Docker image and push to ECR -- or push to DockerHub

# Create ECS cluster
echo "Creating ECS Cluster..."
CLUSTER_NAME=$(aws ecs create-cluster \
  --cluster $CLUSTER_NAME \
  --query 'cluster.clusterName' \
  --output text)
echo "  Cluster Name '$CLUSTER_NAME' CREATED."

# Run a task and view the results
# Create ECS Service

TASK_DEF=$(awk -F'/' '{print $2}' <<< $TASK_DEF_ARN)

echo "Creating ECS Service..."
SERVICE_ID=$(aws ecs create-service \
  --cluster $CLUSTER_NAME \
  --service-name cli-service \
  --launch-type FARGATE \
  --desired-count 1 \
  --task-definition $TASK_DEF \
  --network-configuration \
  "awsvpcConfiguration={subnets=[$SUBNET_PUBLIC_ID,$SUBNET_PRIVATE_ID],securityGroups=[$ECS_SG_ID],assignPublicIp=ENABLED}")


