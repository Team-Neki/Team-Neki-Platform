# Firehose 가 맡는 전송 역할.
#
# 이 역할을 yapp 이 아니라 여기서 만드는 것이 핵심이다. 전송 스트림을 만들려면
# 역할을 Firehose 에 넘겨야 하는데(PassRole), 역할 생성까지 yapp 에 열어주면
# 임의의 권한을 가진 역할을 만들어 자신에게 넘길 수 있어 권한 상승 통로가 된다.
# 역할은 관리자가 코드로 만들고, yapp 에게는 "이 역할만 넘길 수 있다" 만 준다.
resource "aws_iam_role" "firehose_delivery" {
  name = var.delivery_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "firehose.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      # confused deputy 방지. 다른 계정의 Firehose 가 이 역할을 맡지 못한다.
      Condition = {
        StringEquals = {
          "sts:ExternalId" = data.aws_caller_identity.current.account_id
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "firehose_delivery" {
  name = "${var.delivery_role_name}-policy"
  role = aws_iam_role.firehose_delivery.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBucketLevel"
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
        ]
        Resource = "arn:aws:s3:::${var.bucket_name}"
      },
      {
        # prefix 로 막는다. aggregation/ 은 Lambda 만 쓰는 영역이므로 전송
        # 역할이 그쪽에 쓰거나 읽지 못해야 한다.
        Sid    = "AllowObjectsUnderPrefix"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetObject",
          "s3:PutObject",
        ]
        Resource = "arn:aws:s3:::${var.bucket_name}/${var.firehose_s3_prefix}*"
      },
      {
        # 전송 실패 로그. 이게 없으면 Firehose 가 조용히 버리고 원인이 남지 않는다.
        Sid      = "AllowErrorLogging"
        Effect   = "Allow"
        Action   = ["logs:PutLogEvents"]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesisfirehose/${var.delivery_stream_prefix}*:*"
      },
    ]
  })
}

# yapp 에 붙는 구성 권한.
resource "aws_iam_policy" "yapp_firehose" {
  name        = var.yapp_policy_name
  description = "yapp 이 Firehose -> S3 전송 스트림을 구성할 수 있게 한다 (BACKEND-125)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # 이름 접두사로 범위를 묶는다. 계정의 다른 스트림은 건드리지 못한다.
        Sid    = "ManageProjectDeliveryStreams"
        Effect = "Allow"
        Action = [
          "firehose:CreateDeliveryStream",
          "firehose:DeleteDeliveryStream",
          "firehose:DescribeDeliveryStream",
          "firehose:ListTagsForDeliveryStream",
          "firehose:PutRecord",
          "firehose:PutRecordBatch",
          "firehose:StartDeliveryStreamEncryption",
          "firehose:StopDeliveryStreamEncryption",
          "firehose:TagDeliveryStream",
          "firehose:UntagDeliveryStream",
          "firehose:UpdateDestination",
        ]
        Resource = "arn:aws:firehose:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:deliverystream/${var.delivery_stream_prefix}*"
      },
      {
        # 목록 조회는 리소스로 좁힐 수 없다. 읽기 전용이다.
        Sid      = "ListDeliveryStreams"
        Effect   = "Allow"
        Action   = ["firehose:ListDeliveryStreams"]
        Resource = "*"
      },
      {
        # 넘길 수 있는 역할을 하나로 못박고, 받는 서비스까지 조건으로 건다.
        # 조건이 없으면 이 역할을 EC2 같은 다른 서비스에 넘겨 악용할 수 있다.
        Sid      = "PassDeliveryRoleToFirehoseOnly"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = aws_iam_role.firehose_delivery.arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "firehose.amazonaws.com"
          }
        }
      },
      {
        # Terraform 이 전송 스트림을 만들 때 역할을 읽는다.
        Sid      = "ReadDeliveryRole"
        Effect   = "Allow"
        Action   = ["iam:GetRole"]
        Resource = aws_iam_role.firehose_delivery.arn
      },
      {
        # 전송 실패 로그 그룹을 코드로 만들 수 있어야 한다. 역할이 PutLogEvents
        # 권한을 가져도 그룹 자체가 없으면 로깅이 켜지지 않는다.
        Sid    = "ManageFirehoseLogGroups"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DeleteLogGroup",
          "logs:DescribeLogStreams",
          "logs:ListTagsForResource",
          "logs:PutRetentionPolicy",
          "logs:TagResource",
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/kinesisfirehose/${var.delivery_stream_prefix}*"
      },
      {
        # DescribeLogGroups 는 리소스로 좁힐 수 없다. 읽기 전용이다.
        Sid      = "DescribeLogGroups"
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_user_policy_attachment" "yapp_firehose" {
  user       = data.aws_iam_user.yapp.user_name
  policy_arn = aws_iam_policy.yapp_firehose.arn
}
