output "detector_id" {
  description = "The ID of the GuardDuty detector created in the delegated admin (audit) account."
  value       = aws_guardduty_detector.this.id
}

output "organization_configuration_id" {
  description = "The ID of the GuardDuty organisation configuration resource, confirming org-wide auto-enable is active."
  value       = aws_guardduty_organization_configuration.this.id
}
