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
# 31일짜리 달은 마지막 하루가 별도 버킷으로 나뉘어, 그 하루와 앞선 30일에
# 걸쳐 모두 활동한 사용자가 MAU 합산에서 아주 근소하게 중복 집계될 수 있다.
INTERVAL_DAYS = 30


def query(start, end, event_type, metric="uniques", group_by=None):
    """Amplitude Event Segmentation API로 기간 합계/월간 순사용자를 조회한다.

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


def format_change(current, previous):
    """전달 대비 증감률을 '(▲12.3%)' 형태로 만든다. 전달 값이 0이면 계산이 무의미하므로 생략."""
    if previous == 0:
        return " (신규)" if current > 0 else ""
    change = (current - previous) / previous * 100
    arrow = "▲" if change > 0 else ("▼" if change < 0 else "▬")
    return f" ({arrow}{abs(round(change, 1))}%)"


def main():
    pretend_today = os.environ.get("PRETEND_TODAY")
    today = datetime.date.fromisoformat(pretend_today) if pretend_today else datetime.date.today()
    last_day_of_prev_month = today.replace(day=1) - datetime.timedelta(days=1)
    first_day_of_prev_month = last_day_of_prev_month.replace(day=1)

    start = first_day_of_prev_month.strftime("%Y%m%d")
    end = last_day_of_prev_month.strftime("%Y%m%d")
    period_display = f"{first_day_of_prev_month.year}년 {first_day_of_prev_month.month}월"

    prev_last_day = first_day_of_prev_month - datetime.timedelta(days=1)
    prev_first_day = prev_last_day.replace(day=1)
    prev_start = prev_first_day.strftime("%Y%m%d")
    prev_end = prev_last_day.strftime("%Y%m%d")

    mau = query(start, end, "_active", metric="uniques")
    mau_prev = query(prev_start, prev_end, "_active", metric="uniques")
    new_users = query(start, end, "[Amplitude] Application Installed", metric="totals")
    new_users_prev = query(
        prev_start, prev_end, "[Amplitude] Application Installed", metric="totals"
    )

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
    favorite_booth_filter_on = query(start, end, "favorite_booth_filter_on", metric="totals")
    favorite_booth_filter_off = query(start, end, "favorite_booth_filter_off", metric="totals")
    brand_order_save = query(start, end, "brand_order_save", metric="totals")

    pose_filter_toggle = query(start, end, "pose_filter_toggle", metric="totals")
    pose_random_start = query(start, end, "pose_random_start", metric="totals")
    pose_random_session_end = query(start, end, "pose_random_session_end", metric="totals")
    pose_bookmark = query(start, end, "pose_bookmark", metric="totals")
    pose_bookmark_filter = query(start, end, "pose_bookmark_filter", metric="totals")

    photo_detail_view = query(start, end, "photo_detail_view", metric="totals")
    photo_memo_create = query(start, end, "photo_memo_create", metric="totals")
    album_create = query(start, end, "album_create", metric="totals")
    album_add_from_detail = query(start, end, "album_add_from_detail", metric="totals")
    album_add_from_multi = query(start, end, "album_add_from_multi", metric="totals")
    photo_add_to_album = query(start, end, "photo_add_to_album", metric="totals")
    photo_copy = query(start, end, "photo_copy", metric="totals")
    photo_move = query(start, end, "photo_move", metric="totals")
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

    app_open = query(start, end, "app_open", metric="totals")
    session_start = query(start, end, "session_start", metric="totals")
    session_end = query(start, end, "session_end", metric="totals")

    sdk_app_opened = query(start, end, "[Amplitude] Application Opened", metric="totals")
    sdk_app_backgrounded = query(
        start, end, "[Amplitude] Application Backgrounded", metric="totals"
    )
    sdk_app_updated = query(start, end, "[Amplitude] Application Updated", metric="totals")

    mau_change = format_change(mau, mau_prev)
    new_users_change = format_change(new_users, new_users_prev)

    lines = [
        f"## 📆 Amplitude 월간 리포트 · {period_display}",
        f"👥 MAU **{mau}명**{mau_change}  |  신규(설치) **{new_users}명**{new_users_change}  |  🔔 알림 재유입 **{notification_click}회**",
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
        f"🎚️ 저장 필터 on/off **{favorite_booth_filter_on}회 / {favorite_booth_filter_off}회**",
        f"🔀 브랜드 순서 저장 **{brand_order_save}회**",
        "",
        "### 포즈",
        f"🔍 진입 **{pose_view_count}회** ({pose_view_users}명)",
        f"🎚️ 필터 토글 **{pose_filter_toggle}회**",
        f"🎲 랜덤 시작 **{pose_random_start}회**  |  랜덤 종료 **{pose_random_session_end}회**",
        f"🔖 북마크 **{pose_bookmark}회**  |  북마크 필터 **{pose_bookmark_filter}회**",
        "",
        "### 아카이브",
        f"🔍 진입 **{archiving_view_count}회** ({archiving_view_users}명)",
        f"🖼️ 사진 상세 **{photo_detail_view}회**",
        f"📝 메모 작성 **{photo_memo_create}회**",
        f"📁 앨범 생성 **{album_create}회**",
        f"🗂️ 앨범에 추가  단일 **{album_add_from_detail}회**  |  다중 **{album_add_from_multi}회**",
        f"📥 사진 이동  가져오기 **{photo_add_to_album}회**  |  복사 **{photo_copy}회**  |  이동 **{photo_move}회**",
        f"⬆️ 업로드  갤러리 **{gallery}회**  |  QR **{qr}회**",
        "",
        "### 세션 / 앱 진입",
        f"🔓 app_open **{app_open}회**",
        f"▶️ 세션 시작 **{session_start}회**  |  ⏹️ 세션 종료 **{session_end}회**",
        "",
        "### 기타 (SDK 자동수집)",
        f"📲 포그라운드 진입 **{sdk_app_opened}회**  |  백그라운드 전환 **{sdk_app_backgrounded}회**  |  앱 업데이트 **{sdk_app_updated}회**",
        "",
        "-# neki · Amplitude 자동 리포트",
    ]

    payload = {
        "username": "네키 Amplitude 월간봇",
        "avatar_url": "https://i.ifh.cc/PbdkGM.jpg",
        "content": "\n".join(lines),
    }

    resp = requests.post(DISCORD_WEBHOOK_URL, json=payload)
    resp.raise_for_status()
    print(f"전송 완료: {resp.status_code} / {period_display}")


if __name__ == "__main__":
    main()
