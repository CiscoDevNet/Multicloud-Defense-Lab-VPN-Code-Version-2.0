#################################################################################################################################
# ASAv Code
#################################################################################################################################

data "aws_ami" "asav" {
  most_recent = true // you can enable this if you want to deploy more
  owners      = ["aws-marketplace"]

  filter {
    name   = "name"
    values = ["${var.ASA_version}*"]
  }

  # filter {
  #   name   = "product-code"
  #   values = ["663uv4erlxz65quhgaz9cida0"]
  # }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "template_file" "asa_startup_file" {
  template = file("${path.module}/asa_startup_file.txt")
  vars={
    pod_number=var.pod_number
  }
}

# data "template_file" "asa_application_install" {
#   template = file("${path.module}/asa_application_install.sh")
# }



resource "aws_vpc" "asa_vpc" {
  cidr_block           = "172.16.${var.pod_number}.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true
  instance_tenancy     = "default"
  tags = {
    Name = "pod${var.pod_number}-dc"
  }
}

resource "aws_subnet" "asa_mgmt_subnet" {
  vpc_id            = aws_vpc.asa_vpc.id
  cidr_block        = "172.16.${var.pod_number}.128/27"
  availability_zone = "us-west-1a"
    tags = {
    Name = "pod${var.pod_number}-dc-mgmt1"
  }
}


resource "aws_subnet" "asa_outside_subnet" {
 vpc_id            = aws_vpc.asa_vpc.id
  cidr_block        = "172.16.${var.pod_number}.0/27"
  availability_zone = "us-west-1a"
tags = {
    Name = "pod${var.pod_number}-dc-outside1"
  }
}

resource "aws_subnet" "asa_inside_subnet" {
 vpc_id            = aws_vpc.asa_vpc.id
  cidr_block        = "172.16.${var.pod_number}.32/27"
  availability_zone = "us-west-1a"
tags = {
    Name = "pod${var.pod_number}-dc-inside1"
  }
}

resource "aws_subnet" "asa_diag_subnet" {
  vpc_id            = aws_vpc.asa_vpc.id
  cidr_block        = "172.16.${var.pod_number}.192/27"
  availability_zone = "us-west-1a"
tags = {
    Name = "pod${var.pod_number}-dc-diag1"
  }
}

#################################################################################################################################
# Security Group
#################################################################################################################################

resource "aws_security_group" "allow_all" {
  name   = "pod${var.pod_number}-asa-sg"
  vpc_id = aws_vpc.asa_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "pod${var.pod_number}-asa-sg"
  }
}


# # ##################################################################################################################################
# # # Network Interfaces, ASA instance, Attaching the SG to interfaces
# # ##################################################################################################################################
resource "aws_network_interface" "asa_mgmt" {
  description       = "asa-mgmt"
  subnet_id         = aws_subnet.asa_mgmt_subnet.id
  source_dest_check = false
  private_ips       = ["172.16.${var.pod_number}.138"]
}

resource "aws_network_interface" "asa_outside" {
  description       = "asa-outside"
  subnet_id         = aws_subnet.asa_outside_subnet.id
  source_dest_check = false
  private_ips       = ["172.16.${var.pod_number}.15"]
}

resource "aws_network_interface" "asa_inside" {
   description       = "asa-inside"
  subnet_id         = aws_subnet.asa_inside_subnet.id
  source_dest_check = false
  private_ips       = ["172.16.${var.pod_number}.42"]
}

resource "aws_network_interface" "asa_diag" {
   description       = "asa-diag"
  subnet_id         = aws_subnet.asa_diag_subnet.id
  source_dest_check = false
  private_ips       = ["172.16.${var.pod_number}.202"]

}

resource "aws_network_interface_sg_attachment" "asa_mgmt_attachment" {
  depends_on           = [aws_network_interface.asa_mgmt]
  security_group_id    = aws_security_group.allow_all.id
  network_interface_id = aws_network_interface.asa_mgmt.id
}

resource "aws_network_interface_sg_attachment" "asa_outside_attachment" {
 security_group_id    = aws_security_group.allow_all.id
  network_interface_id = aws_network_interface.asa_outside.id
}

resource "aws_network_interface_sg_attachment" "asa_inside_attachment" {
  depends_on           = [aws_network_interface.asa_inside]
  security_group_id    = aws_security_group.allow_all.id
  network_interface_id = aws_network_interface.asa_inside.id
}

resource "aws_network_interface_sg_attachment" "asa_diag_attachment" {
  depends_on           = [aws_network_interface.asa_diag]
  security_group_id    = aws_security_group.allow_all.id
  network_interface_id = aws_network_interface.asa_diag.id
}


# # ##################################################################################################################################
# # #Internet Gateway and Routing Tables
# # ##################################################################################################################################

# # //define the internet gateway
resource "aws_internet_gateway" "int_gw" {
  vpc_id = aws_vpc.asa_vpc.id
  tags = {
    Name = "pod${var.pod_number}-internet-gateway"
  }
}
# //create the route table for outside, inside and DMZ
resource "aws_route_table" "asa_outside_route" {
  vpc_id = aws_vpc.asa_vpc.id
  tags = {
    Name = "pod${var.pod_number}-outside-rt"
  }
}

resource "aws_route_table" "asa_inside_route" {
  vpc_id = aws_vpc.asa_vpc.id
  tags = {
    Name = "pod${var.pod_number}-inside-rt"
  }
}

# # //To define the default routes thru IGW
resource "aws_route" "ext_default_route" {
  route_table_id         = aws_route_table.asa_outside_route.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.int_gw.id
}

resource "aws_route_table_association" "outside_association" {
#   count          = var.outside_subnet_cidr != null ? length(var.outside_subnet_cidr) : length(var.outside_subnet_name)
   subnet_id      = aws_subnet.asa_outside_subnet.id
  route_table_id = aws_route_table.asa_outside_route.id
}

resource "aws_route_table_association" "mgmt_association" {
#   count          = var.mgmt_subnet_cidr != null ? length(var.mgmt_subnet_cidr) : length(var.mgmt_subnet_name)
  subnet_id      = aws_subnet.asa_mgmt_subnet.id
  route_table_id = aws_route_table.asa_outside_route.id
}

resource "aws_route_table_association" "inside_association" {
#   count          = var.inside_subnet_cidr != null ? length(var.inside_subnet_cidr) : length(var.inside_subnet_name)
  subnet_id      = aws_subnet.asa_inside_subnet.id
  route_table_id = aws_route_table.asa_inside_route.id
}


resource "aws_route_table_association" "diag_association" {
#   count          = var.dmz_subnet_cidr != null ? length(var.dmz_subnet_cidr) : length(var.dmz_subnet_name)
  subnet_id      = aws_subnet.asa_diag_subnet.id
  route_table_id = aws_route_table.asa_inside_route.id
}

# # ##################################################################################################################################
# # # AWS External IP address creation and associating it to the mgmt and outside interface. 
# # ##################################################################################################################################
# # //External ip address creation 

resource "aws_eip" "asa_mgmt-EIP" {
#   count = length(var.mgmt_interface) != 0 ? length(var.mgmt_interface) : length(var.mgmt_subnet_name)
#   vpc   = true
  tags = {
    "Name" = "pod${var.pod_number}-ASA-management-ip"
  }
}


resource "aws_eip" "asa_outside-EIP" {
#   count = length(var.outside_interface) != 0 ? length(var.outside_interface) : length(var.outside_subnet_name)
# #   vpc   = true
  tags = {
    "Name" = "pod${var.pod_number}-ASA-outside-ip"
  }
}

resource "aws_eip_association" "asa-mgmt-ip-assocation" {
#   count                = length(var.mgmt_interface) != 0 ? length(var.mgmt_interface) : length(var.mgmt_subnet_name)
  network_interface_id = aws_network_interface.asa_mgmt.id
  allocation_id        = aws_eip.asa_mgmt-EIP.id
}

resource "aws_eip_association" "asa-outside-ip-association" {
#   count                = length(var.outside_interface) != 0 ? length(var.outside_interface) : length(var.outside_subnet_name)
  network_interface_id = aws_network_interface.asa_outside.id
  allocation_id        = aws_eip.asa_outside-EIP.id
}
//keypair

resource "tls_private_key" "key_pair" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content         = tls_private_key.key_pair.private_key_openssh
  filename        = "pod${var.pod_number}-private-key"
  file_permission = 0700
}

resource "local_file" "public_key" {
  content         = tls_private_key.key_pair.public_key_openssh
  filename        = "pod${var.pod_number}-public-key"
  file_permission = 0700
}

resource "aws_key_pair" "sshkeypair" {
  key_name   = "pod${var.pod_number}-keypair"
  public_key = tls_private_key.key_pair.public_key_openssh
}

### Firewall Module

# # ##################################################################################################################################
# # # Create the Cisco ASA01 Instances (First Instance)
# # ##################################################################################################################################

resource "aws_instance" "asav" {
  ami                 = data.aws_ami.asav.id
  instance_type = "c5.2xlarge"
   key_name      = "pod${var.pod_number}-keypair"

  network_interface {
    network_interface_id = aws_network_interface.asa_mgmt.id
    device_index         = 0
  }

  network_interface {
    network_interface_id = aws_network_interface.asa_outside.id
    device_index         = 1
  }

  network_interface {
    network_interface_id = aws_network_interface.asa_inside.id
    device_index         = 2
  }

  network_interface {
    network_interface_id = aws_network_interface.asa_diag.id
    device_index         = 3
  }

  user_data = data.template_file.asa_startup_file.rendered


  tags = {
    Name = "pod${var.pod_number}-ASAv"
  }
}

##################################################################################################################################
# Application Machine
##################################################################################################################################

resource "aws_instance" "AppMachine" {
  ami           = "ami-05c969369880fa2c2"
  instance_type = "t2.micro"
  key_name      = "pod${var.pod_number}-keypair"
  # user_data     = data.template_file.asa_application_install.rendered

  network_interface {
    network_interface_id = aws_network_interface.application_interface.id
    device_index         = 0
  }

  # provisioner "file" {
  #   source      = "./images/aws-app1.png"
  #   destination = "/home/ubuntu/aws-app.png"

  #   connection {
  #     type        = "ssh"
  #     user        = "ubuntu"
  #     private_key = tls_private_key.key_pair.private_key_openssh
  #     host        = aws_eip.app-EIP["${count.index}"].public_ip
  #   }
  # }

  # provisioner "file" {
  #   source      = "./html/index.html"
  #   destination = "/home/ubuntu/index.html"

  #   connection {
  #     type        = "ssh"
  #     user        = "ubuntu"
  #     private_key = tls_private_key.key_pair.private_key_openssh
  #     host        = aws_eip.app-EIP["${count.index}"].public_ip
  #   }
  # }

  # provisioner "file" {
  #   source      = "./html/status${count.index + 1}"
  #   destination = "/home/ubuntu/status"

  #   connection {
  #     type        = "ssh"
  #     user        = "ubuntu"
  #     private_key = tls_private_key.key_pair.private_key_openssh
  #     host        = aws_eip.app-EIP["${count.index}"].public_ip
  #   }
  # }


  tags = {
    Name = "pod${var.pod_number}-test-vm"
    # role = count.index == 0 ? "pod${var.pod_number}-prod" : "pod${var.pod_number}-shared"
  }
}

resource "aws_network_interface" "application_interface" {
  # count = 2

  subnet_id   = aws_subnet.asa_inside_subnet.id
   private_ips =["172.16.${var.pod_number}.40"]# count.index == 0 ? local.app1_nic : local.app2_nic
  tags = {
    Name = "pod${var.pod_number}-app1-nic"
  }
}



#################################################################################################################################
# FTDv Code
#################################################################################################################################
