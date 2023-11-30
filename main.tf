provider "aws" {
  region = "eu-north-1"  # Change to your desired region
}

# Create the IAM Role for Lambda
resource "aws_iam_role" "jedi_lambda_role" {
  name = "jedi_lambda_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# Attach the Lambda execution policy to the IAM role
resource "aws_iam_role_policy_attachment" "lambda_policy" {
 policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
 role       = aws_iam_role.jedi_lambda_role.name
}

# Create policy for jedi-drop and jedi-secret S3 buckets
data "aws_iam_policy_document" "bucket_rw" {
  statement {
    effect    = "Allow"
    actions   = ["s3:*"]
    resources = [
                "arn:aws:s3:::jedi-drop",
                "arn:aws:s3:::jedi-drop/*",
                "arn:aws:s3:::jedi-secret",
                "arn:aws:s3:::jedi-secret/*",
                ]
  }
}

resource "aws_iam_policy" "bucket_rw" {
  name        = "bucket_rw"
  description = "A full S3 access policy"
  policy      = data.aws_iam_policy_document.bucket_rw.json
}

resource "aws_iam_role_policy_attachment" "bucket_attach" {
  role       = aws_iam_role.jedi_lambda_role.name
  policy_arn = aws_iam_policy.bucket_rw.arn
}

## Create S3 Buckets
resource "aws_s3_bucket" "jedi_drop" {
  bucket = "jedi-drop"
}

resource "aws_s3_bucket" "jedi_secret" {
 bucket = "jedi-secret"
}

# Set ACL for the drop bucket
resource "aws_s3_bucket_ownership_controls" "drop" {
  bucket = aws_s3_bucket.jedi_drop.bucket
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "jedi_drop_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.drop]
  bucket = aws_s3_bucket.jedi_drop.bucket
  acl = "private"
}

# Set ACL for the secret bucket
resource "aws_s3_bucket_ownership_controls" "secret" {
  bucket = aws_s3_bucket.jedi_secret.bucket
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "jedi_secret_acl" {
  depends_on = [aws_s3_bucket_ownership_controls.secret]
  bucket = aws_s3_bucket.jedi_secret.bucket
  acl = "private"
}

## Generate a KMS Key
resource "aws_kms_key" "jedi_key" {
 description             = "Jedi Key"
 deletion_window_in_days = 7
 policy = <<EOF
{
 "Version": "2012-10-17",
 "Id": "key-default-1",
 "Statement": [
   {
     "Sid": "Enable IAM User Permissions",
     "Effect": "Allow",
     "Principal": {
       "AWS": "*"
     },
     "Action": "kms:*",
     "Resource": "*"
   }
 ]
}
EOF
}

# Create the Lambda Function
data "archive_file" "lambda" {
  type = "zip"
  source_file = "jedi_lambda.py"
  output_path = "jedi_lambda.zip"
}

resource "aws_lambda_function" "jedi_lambda" {
 function_name = "jedi_lambda"
 handler       = "jedi_lambda.lambda_handler"
 runtime       = "python3.8"
 filename      = "jedi_lambda.zip"

 role = aws_iam_role.jedi_lambda_role.arn

 environment {
   variables = {
     jedi_key    = aws_kms_key.jedi_key.key_id
     jedi_drop   = aws_s3_bucket.jedi_drop.bucket,
     jedi_secret = aws_s3_bucket.jedi_secret.bucket,
   }
 }

 source_code_hash = filebase64sha256("jedi_lambda.py")
}

# Lambda IAM Role Permissions
resource "aws_lambda_permission" "allow_s3" {
 statement_id  = "AllowExecutionFromS3"
 action        = "lambda:InvokeFunction"
 function_name = aws_lambda_function.jedi_lambda.function_name
 principal     = "s3.amazonaws.com"
}

# Trigger the lambda when an object is created in the drop bucket
resource "aws_s3_bucket_notification" "drop_trigger" {
  bucket = aws_s3_bucket.jedi_drop.bucket
  lambda_function {
    lambda_function_arn = aws_lambda_function.jedi_lambda.arn
    events              = ["s3:ObjectCreated:*"]
  }
}

