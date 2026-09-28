import datetime
import json
import os

import requests

PROJECT_ID = "847661"  # NEKI_PROD
API_KEY = os.environ["AMPLITUDE_API_KEY"]
SECRET_KEY = os.environ["AMPLITUDE_SECRET_KEY"]
DISCORD_WEBHOOK_URL = os.environ["DISCORD_WEBHOOK_URL"]

SEGMENTATION_URL = "https://amplitude.com/api/2/events/segmentation"

# Amplitude Segmentation API의 interval(i)은 1/7/30만 허용한다.
# 7로 두고 start~end를 정확히 7일로 맞추면 uniques가 그 주간의 실제 중복제거 인원(WAU)으로 나온다.
INTERVAL_DAYS = 7


def query(start, end, event_type, metric="uniques", group_by=None):
    """Amplitude Event Segmentation API로 기간 합계/주간 순사용자를 조회한다.

    group_by가 있으면 (label, value) 리스트를, 없으면 단일 값을 반환한다.
    """
    event = {"event_type": event_type}
    if group_by:
        event["group_by"] = group_by

    params = {
        "e": json.dumps(event),
        "start": start,
        "end": end,
        "m": metric,
        "i": INTERVAL_DAYS,
    }
    resp = requests.get(
        SEGMENTATION_URL,
        params=params,
        auth=(API_KEY, SECRET_KEY),
        timeout=15,
    )
    if resp.status_code == 400:
        # 한 번도 발생한 적 없는 이벤트는 Amplitude가 "Invalid <event>"로 거부한다.
        # 데이터가 없다는 뜻이므로 0으로 취급한다.
        print(f"경고: {event_type} 조회 실패(400), 0으로 처리: {resp.text}")
        return [] if group_by else 0
    resp.raise_for_status()
    data = resp.json()["data"]

    if group_by:
        labels = data.get("seriesLabels", [])
        series = data.get("series", [])
        result = []
        for i, label in enumerate(labels):
            value = label[-1] if isinstance(label, list) else label
            total = sum(series[i]) if i < len(series) and series[i] else 0
            result.append((value, total))
        return result

    series = data.get("series", [[0]])
    return sum(series[0]) if series and series[0] else 0


def main():
    pretend_today = os.environ.get("PRETEND_TODAY")
    today = datetime.date.fromisoformat(pretend_today) if pretend_today else datetime.date.today()
    last_sunday = today - datetime.timedelta(days=today.weekday() + 1)
    last_monday = last_sunday - datetime.timedelta(days=6)

    start = last_monday.strftime("%Y%m%d")
    end = last_sunday.strftime("%Y%m%d")
    period_display = f"{last_monday.isoformat()} ~ {last_sunday.isoformat()}"

    wau = query(start, end, "_active", metric="uniques")
    new_users = query(start, end, "[Amplitude] Application Installed", metric="totals")

    def totals_and_users(event_type):
        return query(start, end, event_type, metric="totals"), query(
            start, end, event_type, metric="uniques"
        )

    map_view_count, map_view_users = totals_and_users("map_view")
    booth_select_count, booth_select_users = totals_and_users("booth_select")
    pose_view_count, pose_view_users = totals_and_users("pose_view")
    archiving_view_count, archiving_view_users = totals_and_users("archiving_view")

    map_re_search = query(start, end, "map_re_search", metric="totals")
    map_route_click = query(start, end, "map_route_click", metric="totals")
    map_brand_filter_toggle = query(start, end, "map_brand_filter_toggle", metric="totals")
    booth_favorite_add = query(start, end, "booth_favorite_add", metric="totals")
    booth_favorite_remove = query(start, end, "booth_favorite_remove", metric="totals")
    favorite_booth_view = query(start, end, "favorite_booth_view", metric="totals")

    pose_filter_toggle = query(start, end, "pose_filter_toggle", metric="totals")
    pose_random_start = query(start, end, "pose_random_start", metric="totals")
    pose_bookmark = query(start, end, "pose_bookmark", metric="totals")
    pose_bookmark_filter = query(start, end, "pose_bookmark_filter", metric="totals")

    photo_detail_view = query(start, end, "photo_detail_view", metric="totals")
    photo_memo_create = query(start, end, "photo_memo_create", metric="totals")
    album_create = query(start, end, "album_create", metric="totals")
    upload_breakdown = dict(
        query(
            start,
            end,
            "photo_upload",
            metric="totals",
            group_by=[{"type": "event", "value": "method"}],
        )
    )
    gallery = upload_breakdown.get("gallery", 0)
    qr = upload_breakdown.get("qr", 0)

    notification_click = query(start, end, "notification_click", metric="totals")
    mypage_logout = query(start, end, "mypage_logout", metric="totals")
    mypage_withdraw = query(start, end, "mypage_withdraw", metric="totals")

    lines = [
        f"📊 **Amplitude 주간 리포트 · {period_display}**",
        f"👥 WAU **{wau}명**  |  신규(설치) **{new_users}명**  |  🔔 알림 재유입 **{notification_click}회**",
        f"↩️ 로그아웃 **{mypage_logout}회**  |  ⚠️ 탈퇴 **{mypage_withdraw}회**",
        "",
        "### 지도",
        f"🔍 진입 **{map_view_count}회** ({map_view_users}명)",
        f"🔁 재검색 **{map_re_search}회**",
        f"🏷️ 브랜드 필터 **{map_brand_filter_toggle}회**",
        f"📍 부스 선택 **{booth_select_count}회** ({booth_select_users}명)",
        f"🧭 길찾기 **{map_route_click}회**",
        f"⭐ 즐겨찾기 추가/삭제 **{booth_favorite_add}회 / {booth_favorite_remove}회**",
        f"👀 즐겨찾기 조회 **{favorite_booth_view}회**",
        "",
        "### 포즈",
        f"🔍 진입 **{pose_view_count}회** ({pose_view_users}명)",
        f"🎚️ 필터 토글 **{pose_filter_toggle}회**",
        f"🎲 랜덤 시작 **{pose_random_start}회**",
        f"🔖 북마크 **{pose_bookmark}회**  |  북마크 필터 **{pose_bookmark_filter}회**",
        "",
        "### 아카이브",
        f"🔍 진입 **{archiving_view_count}회** ({archiving_view_users}명)",
        f"🖼️ 사진 상세 **{photo_detail_view}회**",
        f"📝 메모 작성 **{photo_memo_create}회**",
        f"📁 앨범 생성 **{album_create}회**",
        f"⬆️ 업로드  갤러리 **{gallery}회**  |  QR **{qr}회**",
        "",
        "-# neki · Amplitude 자동 리포트",
    ]

    payload = {
        "username": "네키 Amplitude 봇",
        "avatar_url": "https://i.ifh.cc/PbdkGM.jpg",
        "content": "\n".join(lines),
    }

    resp = requests.post(DISCORD_WEBHOOK_URL, json=payload)
    resp.raise_for_status()
    print(f"전송 완료: {resp.status_code} / {period_display}")


if __name__ == "__main__":
    main()
