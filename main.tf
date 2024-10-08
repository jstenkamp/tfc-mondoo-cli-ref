provider "aws" {
    region = var.aws_region
 }

# Network & Routing
# VPC 

resource "aws_vpc" "demo_vpc" {
  cidr_block           = var.network_address_space
  enable_dns_hostnames = "true"

  tags = {
    Name = "${var.name}-vpc"
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name = "name"
    #values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
    #values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

# Get latest Windows Server 2019 AMI
data "aws_ami" "windows-2019" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2019-English-Full-Base*"]
  }
}


# Internet Gateways and route table

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.demo_vpc.id
}

resource "aws_route_table" "rtb" {
  vpc_id = aws_vpc.demo_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "${var.name}-igw"
  }
}

resource "aws_subnet" "dmz_subnet" {
  vpc_id                  = aws_vpc.demo_vpc.id
  cidr_block              = cidrsubnet(var.network_address_space, 8, 1)
  map_public_ip_on_launch = "true"
  #availability_zone       = data.aws_availability_zones.available.names[0]

  tags = {
    Name        = "dmz-subnet"
  }
}

resource "aws_route_table_association" "dmz-subnet" {
  subnet_id      = aws_subnet.dmz_subnet.*.id[0]
  route_table_id = aws_route_table.rtb.id
}

## Access and Security Groups

resource "aws_security_group" "linux" {
  name        = "${var.name}-linux-sg"
  description = "Linux"
  vpc_id      = aws_vpc.demo_vpc.id
}

resource "aws_security_group_rule" "jh-ssh" {
  security_group_id = aws_security_group.linux.id
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "jh-egress" {
  security_group_id = aws_security_group.linux.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}


####
resource "aws_security_group" "windows" {
  name        = "${var.name}-windows-sg"
  description = "Windows"
  vpc_id      = aws_vpc.demo_vpc.id
}

resource "aws_security_group_rule" "win-rdp-tcp" {
  security_group_id = aws_security_group.windows.id
  type              = "ingress"
  from_port         = 3389
  to_port           = 3389
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "win-rdp-ucp" {
  security_group_id = aws_security_group.windows.id
  type              = "ingress"
  from_port         = 3389
  to_port           = 3389
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
}


resource "aws_security_group_rule" "win-egress" {
  security_group_id = aws_security_group.windows.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}


resource "aws_instance" "linux" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.dmz_subnet.id
  private_ip                  = cidrhost(aws_subnet.dmz_subnet.cidr_block, 10)
  associate_public_ip_address = "true"
  vpc_security_group_ids      = [aws_security_group.linux.id]
  key_name                    = var.key_name
  user_data                   = <<-EOF
    #!/bin/bash
    export MONDOO_REGISTRATION_TOKEN='${var.linux_reg_token}'
    curl -sSL https://install.mondoo.com/sh | bash -s -- -u enable -s enable -t $MONDOO_REGISTRATION_TOKEN
    EOF
  
  
  tags = {
    Name        = "linux-01"
  }
}


data "template_file" "windows" {
  template = file("${path.root}/templates/win_userdata.ps")

  vars = {
    windows_password = var.windows_password
    win_reg_token = var.win_reg_token
  }
}

data "template_cloudinit_config" "windows" {
  gzip          = true
  base64_encode = true
  part {
    content_type = "text/x-shellscript"
    content      = data.template_file.windows.rendered
  }
}




resource "aws_instance" "windows" {
  ami                         = data.aws_ami.windows-2019.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.dmz_subnet.id
  private_ip                  = cidrhost(aws_subnet.dmz_subnet.cidr_block, 20)
  associate_public_ip_address = "true"
  vpc_security_group_ids      = [aws_security_group.windows.id]
  key_name                    = var.key_name
  user_data = data.template_file.windows.rendered
  
  tags = {
    Name        = "winsrv-01"
  }
}
