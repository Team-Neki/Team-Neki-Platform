# 기존 리소스를 state 로 가져온다.
#
# CLI 로 terraform import 를 치지 않고 블록으로 두는 이유는, 무엇을 가져왔는지가
# 코드로 남고 PR 에서 plan 으로 검증되기 때문이다. CLI import 는 기록이 셸
# 히스토리에만 남는다.
#
# apply 가 끝나면 이 파일은 지워도 된다. 남겨도 동작에는 영향이 없다.
# state 에 이미 있으면 import 블록은 무시된다.

import {
  for_each = local.buckets
  to       = aws_s3_bucket.imported[each.key]
  id       = each.key
}

import {
  for_each = local.buckets
  to       = aws_s3_bucket_public_access_block.imported[each.key]
  id       = each.key
}

import {
  for_each = local.buckets
  to       = aws_s3_bucket_server_side_encryption_configuration.imported[each.key]
  id       = each.key
}

import {
  for_each = local.buckets
  to       = aws_s3_bucket_ownership_controls.imported[each.key]
  id       = each.key
}

import {
  for_each = local.cors_buckets
  to       = aws_s3_bucket_cors_configuration.imported[each.key]
  id       = each.key
}
