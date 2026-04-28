# BAD PATTERN: Open security groups — SSH and all-traffic from 0.0.0.0/0.
# This exposes instances to the public internet. Should be flagged.

resource "aws_security_group" "bad_open_ssh" {
  name        = "allow-all-ssh"
  description = "Allow SSH from anywhere"
  vpc_id      = var.vpc_id

  # BAD: SSH open to the world
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # BAD: all traffic from anywhere
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Missing tags — no Environment, ManagedBy
}

resource "aws_security_group" "bad_rdp_open" {
  name   = "allow-rdp-all"
  vpc_id = var.vpc_id

  # BAD: RDP open to the world
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
