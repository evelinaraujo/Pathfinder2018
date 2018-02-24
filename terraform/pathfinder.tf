provider "aws" {
  region = "us-west-2"
}

variable "vpc-id" {
  description = "ID of your VPC"
  default = ""
}

variable "ami" {
  default = " ami-79873901"
}

variable "bastion-key-name"{
  description = "name of bastion key"
  default = ""
}

variable "ec2-key-name" {
  description = "name of web-server key"
  default = ""
}

## Public subnet (4096 IP addresses)
resource "aws_subnet" "public-subnet" {
  vpc_id                  = "${var.vpc-id}"
  cidr_block              = "172.31.0.0/20"
  map_public_ip_on_launch = true
  availability_zone       = "us-west-2b"

  tags = {
    Name = "Public Subnet"
  }
}

## Private Subnet (4096 IP addresses)

resource "aws_subnet" "private-subnet" {
  vpc_id            = "${var.vpc-id}"
  cidr_block        = "172.31.16.0/20"
  availability_zone = "us-west-2a"

  tags = {
    Name = "Private Subnet 2a"
  }
}

## Internet Gateway

resource "aws_internet_gateway" "gateway" {
  vpc_id = "${var.vpc-id}"

  tags = {
    Name = "Internet Gateway"
  }
}

## Elastic IP address for NAT gateway
resource "aws_eip" "nat-eip" {
  vpc        = true
  depends_on = ["aws_internet_gateway.gateway"]
}

## Nat Gateway
resource "aws_nat_gateway" "nat-gateway" {
  allocation_id = "${aws_eip.nat-eip.id}"
  subnet_id     = "${aws_subnet.public-subnet.id}"
  depends_on    = ["aws_internet_gateway.gateway"]
}

## Public Route Table

resource "aws_route_table" "public-route-table" {
  vpc_id = "${var.vpc-id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gateway.id}"
  }

  tags = {
    Name = "Public route table"
  }
}

## Private Route Table
resource "aws_route_table" "private-route-table" {
  vpc_id = "${var.vpc-id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_nat_gateway.nat-gateway.id}"
  }

  tags {
    Name = "Private route table"
  }
}

## Public Route Table Association
resource "aws_route_table_association" "public-subnet-association" {
  subnet_id      = "${aws_subnet.public-subnet.id}"
  route_table_id = "${aws_route_table.public-route-table.id}"
}

## Private Route Table Association
resource "aws_route_table_association" "private-subnet-association" {
  subnet_id      = "${aws_subnet.private-subnet.id}"
  route_table_id = "${aws_route_table.private-route-table.id}"
}

## Security Group for Web-Server
resource "aws_security_group" "web-server-sg" {
  vpc_id = "${var.vpc-id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/16"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

## Security group that allows SSH to Bastion Host
resource "aws_security_group" "allow-ssh-bastion" {
  name        = "allow_ssh_bastion"
  vpc_id      = "${var.vpc-id}"
  description = "Allow local inbound ssh traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/16", "172.28.0.0/16", "130.166.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

## Security Group for Load Balancer

resource "aws_security_group" "lb-security-group" {
  name        = "lb-security-group"
  vpc_id      = "${var.vpc-id}"
  description = "Allow web incoming traffic to load balancer"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

## Bastion Host
resource "aws_instance" "bastion" {
  ami                         = "${var.ami}"
  instance_type               = "t2.micro"
  vpc_security_group_ids      = ["${aws_security_group.allow-ssh-bastion.id}"]
  subnet_id                   = "${aws_subnet.public-subnet.id}"
  associate_public_ip_address = true
  key_name                    = "${var.bastion-key-name}"

  tags {
    Name = "bastion"
  }
}

resource "aws_instance" "ec2-instance" {
  ami                         = "${var.ami}"
  instance_type               = "t2.micro"
  vpc_security_group_ids      = ["${aws_security_group.web-server-sg.id}"]
  subnet_id                   = "${aws_subnet.private-subnet.id}"
  associate_public_ip_address = false
  key_name                    = "${var.ec2-key-name}"
}

resource "aws_elb" "elb" {
  name            = "elb"
  security_groups = ["$aws_security_group.lb-security-group}"]
  subnets         = ["${aws_subnet.public-subnet.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  listener {
    instance_port      = 80
    instance_protocol  = "http"
    lb_port            = 443
    lb_protocol        = "https"
  }

  health_check {
    healthy_threshold   = "10"
    unhealthy_threshold = "2"
    target              = "TCP:80"
    interval            = "10"
    timeout             = "2"
  }

  connection_draining         = "true"
  connection_draining_timeout = "300"
  instances                   = ["${aws_instance.ec2-instance.id}"]

}
