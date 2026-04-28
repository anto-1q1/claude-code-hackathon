# BAD PATTERN: Over-permissive IAM — wildcard actions and resources.
# Should be flagged: "Action": "*" and "Resource": "*" without conditions.

resource "aws_iam_role_policy" "bad_wildcard" {
  name = "bad-all-permissions"
  role = aws_iam_role.app.id

  # BAD: full admin equivalent
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "bad_s3_star" {
  name = "bad-s3-star"
  role = aws_iam_role.app.id

  # BAD: all S3 actions on all buckets
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:*"
        Resource = "*"
      }
    ]
  })
}
