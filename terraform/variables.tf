variable "region" {
  description = "AWS region to deploy resources"
  type        = string
}

variable "project_name" {
  description = "Project name to prefix resource names"
  type        = string
}

variable "cognito_users" {
  description = "List of email addresses for Cognito users. Must be a valid email address."
  type        = list(string)
  validation {
    condition     = alltrue([for email in var.cognito_users : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))])
    error_message = "Invalid email address format in cognito_users"
  }
}
