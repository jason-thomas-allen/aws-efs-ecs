# aws-efs-ecs

### Step 1: Create a VPC and subnets

aws ec2 create-vpc --cidr-block 10.0.0.0/16

-> "VpcId": "vpc-0414a605b4056e3f2"

aws ec2 create-subnet --vpc-id vpc-0414a605b4056e3f2 --cidr-block 10.0.1.0/24

-> "SubnetId": "subnet-06b6d08f4bb4fc6e4"

aws ec2 create-subnet --vpc-id vpc-0414a605b4056e3f2 --cidr-block 10.0.0.0/24

-> "SubnetId": "subnet-08d880757d17d197b"

### Step 2: Make your subnet public

aws ec2 create-internet-gateway

-> "InternetGatewayId": "igw-0940858e81c600a65"

aws ec2 attach-internet-gateway --vpc-id vpc-0414a605b4056e3f2 --internet-gateway-id igw-0940858e81c600a65

aws ec2 create-route-table --vpc-id vpc-0414a605b4056e3f2

-> "RouteTableId": "rtb-0f4eb7f9b8df8c9cc"

#### Create a route in the route table that points all traffic (0.0.0.0/0) to the Internet gateway.

aws ec2 create-route --route-table-id rtb-0f4eb7f9b8df8c9cc --destination-cidr-block 0.0.0.0/0 --gateway-id igw-0940858e81c600a65

#### To confirm that your route has been created and is active, you can describe the route table and view the results.

aws ec2 describe-route-tables --route-table-id rtb-0f4eb7f9b8df8c9cc

#### The route table is currently not associated with any subnet. You need to associate it with a subnet in your VPC so that traffic from that subnet is routed to the internet gateway. First, use the describe-subnets command to get your subnet IDs. You can use the --filter option to return the subnets for your new VPC only, and the --query option to return only the subnet IDs and their CIDR blocks.

aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-0414a605b4056e3f2" --query "Subnets[*].{ID:SubnetId,CIDR:CidrBlock}"

#### Make subnet public by association to the custom route table.

aws ec2 associate-route-table --subnet-id subnet-06b6d08f4bb4fc6e4 --route-table-id rtb-0f4eb7f9b8df8c9cc

#### You can optionally modify the public IP addressing behavior of your subnet so that an instance launched into the subnet automatically receives a public IP address. Otherwise, you should associate an Elastic IP address with your instance after launch so that it's reachable from the internet.

aws ec2 modify-subnet-attribute --subnet-id subnet-06b6d08f4bb4fc6e4 --map-public-ip-on-launch

### Step 3: Launch an instance into your subnet

aws ec2 create-key-pair --key-name MyKeyPair --query "KeyMaterial" --output text > MyKeyPair.pem
chmod 400 MyKeyPair.pem

aws ec2 create-security-group --group-name SSHAccess --description "Security group for SSH access" --vpc-id vpc-0414a605b4056e3f2

-> "GroupId": "sg-027e7e93479f3069d"

#### Add a rule that allows SSH access from anywhere using the authorize-security-group-ingress command.

#### If you use 0.0.0.0/0, you enable all IPv4 addresses to access your instance using SSH. This is acceptable for this short exercise, but in production, authorize only a specific IP address or range of addresses.

aws ec2 authorize-security-group-ingress --group-id sg-027e7e93479f3069d --protocol tcp --port 22 --cidr 0.0.0.0/0

-> "SecurityGroupRuleId": "sgr-08334d7f9d2002772"

#### Launch an instance into your public subnet, using the security group and key pair you've created. In the output, take note of the instance ID for your instance.

aws ec2 run-instances --image-id ami-082105f875acab993 \
--count 1 --instance-type t2.micro --key-name MyKeyPair \
--security-group-ids sg-027e7e93479f3069d --subnet-id subnet-06b6d08f4bb4fc6e4

-> InstanceId": "i-06e664c7f5fc35c8c",

#### Check its running

aws ec2 describe-instances --instance-id i-06e664c7f5fc35c8c

-> "PublicIpAddress": "52.77.255.65"

ssh -i "MyKeyPair.pem" ec2-user@52.77.255.65

# ECS

### Step 1: Create an Amazon ECS cluster

aws ecs create-cluster --cluster-name cli-cluster

#### Create security group for ECS Service

#### Create service

aws ecs create-service --cluster cli-cluster \
--service-name cli-service \
--launch-type FARGATE \
--desired-count 1 \
--task-definition first-run-task-definition:1 \
--network-configuration "awsvpcConfiguration={subnets=[subnet-02a6e4237553cc48a,subnet-0a05adb1788b04b40],securityGroups=[sg-02796d6831c52b5ad],assignPublicIp=ENABLED}"

# Step 2: Create a security group for the Amazon EFS file system

# Step 3: Create an Amazon EFS file system

# Step 4: Add content to the Amazon EFS file system

# Step 5: Create a task definition

# Step 6: Run a task and view the results

### Step 4: Clean up

aws ec2 terminate-instances --instance-ids i-06e664c7f5fc35c8c

aws ec2 delete-security-group --group-id sg-027e7e93479f3069d

aws ec2 delete-subnet --subnet-id subnet-06b6d08f4bb4fc6e4
aws ec2 delete-subnet --subnet-id subnet-08d880757d17d197b

aws ec2 delete-route-table --route-table-id rtb-0f4eb7f9b8df8c9cc

aws ec2 detach-internet-gateway --internet-gateway-id igw-0940858e81c600a65 --vpc-id vpc-0414a605b4056e3f2

aws ec2 delete-internet-gateway --internet-gateway-id igw-0940858e81c600a65

aws ec2 delete-vpc --vpc-id vpc-0414a605b4056e3f2
