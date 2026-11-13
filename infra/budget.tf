# Safety net: an email as soon as the account spends anything.
# (Plain budgets with email alerts are free.)
resource "aws_budgets_budget" "alert" {
  count = var.budget_email == "" ? 0 : 1

  name         = "${var.project}-cost-alert"
  budget_type  = "COST"
  limit_amount = "1"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # First cent spent ($0.01 = 1% of $1)
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 1
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }

  # The whole dollar
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }
}
