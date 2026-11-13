# Latest Ubuntu 24.04 LTS image published by Canonical.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# ---- Identity of the server -------------------------------------------------
# The instance gets a role (no keys on disk). It allows two things:
#   - AWS SSM may manage it (this is how deploys reach it, instead of SSH)
#   - it may PULL images from our ECR repository

resource "aws_iam_role" "instance" {
  name = "${var.project}-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "instance_ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "instance_ecr_pull" {
  name = "ecr-pull"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*" # this action does not support resource-level permissions
      },
      {
        Sid    = "PullFromOurRepositoryOnly"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
        ]
        Resource = aws_ecr_repository.app.arn
      },
    ]
  })
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.project}-instance"
  role = aws_iam_role.instance.name
}

# ---- The server -------------------------------------------------------------

resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  # First-boot script: swap, Docker, clone the repo, ./provision.sh
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    github_repo  = var.github_repo
    ecr_registry = split("/", aws_ecr_repository.app.repository_url)[0]
  })
  user_data_replace_on_change = true

  # T3 instances default to "unlimited" CPU credits, which can cost money
  # under sustained load. "standard" can never exceed the free allowance.
  credit_specification {
    cpu_credits = "standard"
  }

  # Require IMDSv2 (session tokens) for the instance metadata service.
  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 16 # GB; the free tier covers 30
    encrypted   = true
  }

  # A newer Ubuntu image must not silently replace a running server.
  lifecycle {
    ignore_changes = [ami]
  }

  # The instance needs internet access on first boot.
  depends_on = [aws_route_table_association.public]

  tags = { Name = var.project }
}
