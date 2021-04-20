variable "aws_region_id" {
  type    = string
  default = "us-east-1"
}

variable "source_s3_bucket_path" {
  type    = string
  default = "bideep-packerbuild"
}

variable "secrets_holder_id" {
  type    = string
  default = "AMI-Secrets"
}

data "amazon-secretsmanager" "default" {
  name = "AMI-Secrets"
  version_stage = "AWSCURRENT"
}

locals { 
  timestamp = regex_replace(timestamp(), "[- TZ:]", "") 
  qualys_activation_id  = jsondecode(data.amazon-secretsmanager.default.secret_string)["Qualys_Activation_Id"]
  dd_key_id  = jsondecode(data.amazon-secretsmanager.default.secret_string)["DD_Key_Id"]
}

source "amazon-ebs" "default" {
  ami_name      = "RHEL-8.3.0_HVM-Base-${local.timestamp}"
  ami_users     = ["000000000"]
  associate_public_ip_address = true
  instance_type = "t3.medium"
  region        = "us-east-1"
  source_ami    = "ami-096fda3c22c1c990a"
  ssh_timeout   = "5m"
  ssh_username  = "ec2-user"
  subnet_id     = "subnet-0000000"
  vpc_id        = "vpc-0000000"
  iam_instance_profile = "packer-builder"
}

build {
  sources = ["source.amazon-ebs.default"]

  provisioner "shell" {
    inline = [
    "#!/usr/bin/env bash",
    "# ------aws cli installation -------" ,
    "sudo yum update -y",
    "sudo yum -y install unzip",
    "sudo curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64-2.0.30.zip' -o 'awscliv2.zip'", 
    "unzip ./awscliv2.zip", 
    "sudo ./aws/install",
    
    "AWS_REGION_ID=${var.aws_region_id}",
    "source_s3_bucket_path=${var.source_s3_bucket_path}",

    "# ---- Download binaries and scripts --------" ,
    "sudo /usr/local/aws-cli/v2/current/bin/aws s3 cp s3://$source_s3_bucket_path/binaries/QualysCloudAgent.rpm /tmp/QualysCloudAgent.rpm --region=$AWS_REGION_ID",
    "sudo /usr/local/aws-cli/v2/current/bin/aws s3 cp s3://$source_s3_bucket_path/binaries/dd-agent-install_script.sh /tmp/dd-agent-install_script.sh --region=$AWS_REGION_ID",
    "sudo /usr/local/aws-cli/v2/current/bin/aws s3 cp s3://$source_s3_bucket_path/scripts/linux_hardening.sh /tmp/linux_hardening.sh",
    
    "# ---- Agent installation  --------" ,
    "sudo chmod +x /tmp/dd-agent-install_script.sh",
    "sudo rpm -ivh /tmp/QualysCloudAgent.rpm", 
    "sudo /usr/local/qualys/cloud-agent/bin/qualys-cloud-agent.sh ActivationId=${local.qualys_activation_id}", 
    "sudo DD_AGENT_MAJOR_VERSION=7 DD_API_KEY=${local.dd_key_id} bash -c '$(curl -L https://s3.amazonaws.com/dd-agent/scripts/install_script.sh)'",
    "sudo systemctl start datadog-agent"

    "# ---- Hardening Linux server ---- " ,
    "sudo chmod +x /tmp/linux_hardening.sh" ,
    "sudo /tmp/linux_hardening.sh"
    ]
  }
}
