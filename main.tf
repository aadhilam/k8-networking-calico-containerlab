provider "aws" {
  region = "us-east-1"
}

resource "aws_key_pair" "key" {
  key_name   = "containerlab-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_instance" "clab" {
  ami           = "ami-0fc5d935ebf8bc3bc" # Ubuntu 22.04 LTS
  instance_type = "t3.2xlarge"
  key_name      = aws_key_pair.key.key_name

  root_block_device {
    volume_size           = 50    # Size in GB (default is typically 8GB)
    volume_type           = "gp3" # General Purpose SSD
    delete_on_termination = true
  }

  tags = {
    Name = "containerlab-ec2"
  }

  provisioner "local-exec" {
    command = "echo ${self.public_ip} > ec2_ip.txt"
  }
}