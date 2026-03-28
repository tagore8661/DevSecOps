provider "aws" {
  region = "us-east-1"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "vault_demo" {
  bucket = "terraform-vault-${random_id.bucket_suffix.hex}"

  tags = {
    Name      = "Terraform Vault Demo"
    ManagedBy = "Terraform"
  }
}

output "bucket_name" {
  value = aws_s3_bucket.vault_demo.id
}