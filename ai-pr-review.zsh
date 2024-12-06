#!/bin/zsh

# ANTHROPIC_API_KEY 환경변수 확인
if [[ -z "$ANTHROPIC_API_KEY" ]]; then
  echo "에러: ANTHROPIC_API_KEY 환경변수가 설정되지 않았습니다" >&2
  exit 1
fi

# 인자 파싱
for arg in "$@"; do
  case $arg in
    --compare=*)
      compare_branch="${arg#*=}"
      ;;
  esac
done

# compare_branch가 지정되지 않은 경우 기본값 'develop' 사용
compare_branch=${compare_branch:-develop}

# 지정된 브랜치와 비교하여 diff 생성
git fetch origin ${compare_branch}:${compare_branch} 2>/dev/null || true
git diff ${compare_branch} > pr.diff

# diff 내용 읽기
diff_content=$(cat pr.diff)

# 프롬프트 준비
prompt="당신은 명확하고 상세한 PR 메시지를 작성하는 전문 개발자입니다.
PR template과 git diff를 분석하여 적절한 PR 메시지를 생성해주세요.

PR 메시지는 다음 가이드라인을 따라야 합니다:
- PR의 목적과 주요 변경사항을 명확히 설명할 것
- 기술적 결정사항이나 고려사항이 있다면 포함할 것
- 테스트 방법이나 주의사항이 있다면 명시할 것
- 기술 용어는 영문으로, 설명은 한국어로 작성할 것

위 가이드라인에 따라 PR 메시지를 생성해주세요.

변경사항:
\`\`\`diff
$diff_content
\`\`\`"

# JSON용 프롬프트 이스케이프
json_escaped_prompt=$(jq -n --arg prompt "$prompt" '$prompt')

# Claude API 호출
response=$(curl -s https://api.anthropic.com/v1/messages \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    --data-raw "{
        \"model\": \"claude-3-5-sonnet-20241022\",
        \"max_tokens\": 4096,
        \"messages\": [
            {
                \"role\": \"user\",
                \"content\": ${json_escaped_prompt}
            }
        ]
    }")

# API 응답에서 리뷰 내용만 추출
review_content=$(echo "$response" | tr -d '\000-\037' | jq -r '.content[0].text')

# 에러 발생 시에만 디버그 정보 출력
if [[ -z "$review_content" || "$review_content" == "null" ]]; then
  echo "에러: PR 리뷰 생성 실패" >&2
  echo "API 응답:" >&2
  echo "$response" | tr -d '\000-\037' | jq '.' >&2
  exit 1
fi

# 성공 시 리뷰 내용만 출력
echo "$review_content"

# 임시 파일 삭제
rm -f pr.diff
