# Simple Terraform configuration for testing TFC API workflow
# This creates a random pet name - harmless resource for testing

terraform {
  required_version = ">= 1.13.5"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3"
    }
  }

  # Note: We don't configure the cloud block here
  # TFC API-driven workspaces don't use the cloud block
  # The workspace configuration exists in TFC, not in code
}

variable "bu_projects" {
  type = string
  default = ""
}

# # A simple random pet resource to test deployments
# resource "random_pet" "example_pet" {
#   length    = 3
#   separator = "-"
# }

# output "pet_name" {
#   description = "The generated random pet name"
#   value       = random_pet.example_pet.id
#}

# resource "random_id" "example_id" {
#   byte_length = 4
# }

# output "example_id" {
#   description = "The generated random ID"
#   value       = random_id.example_id.hex
# }