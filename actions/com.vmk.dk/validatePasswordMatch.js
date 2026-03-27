def handler(context, inputs):
    print("=== 비밀번호 일치 검증 Action 시작 ===")
    
    pw1 = inputs.get("pw1")
    pw2 = inputs.get("pw2")

    # 보안상 비밀번호 자체는 로그에 남기지 않고 길이만 확인
    if pw1:
        print(f"로그: 첫 번째 비밀번호 입력됨 (길이: {len(pw1)})")
    else:
        print("로그: 첫 번째 비밀번호가 비어있음")

    if pw2:
        print(f"로그: 확인용 비밀번호 입력됨 (길이: {len(pw2)})")
    else:
        print("로그: 확인용 비밀번호가 비어있음")

    # 둘 중 하나라도 입력되지 않았으면 아직 검증하지 않음 (사용자가 입력 중인 상태)
    if not pw1 or not pw2:
        print("로그: 입력 완료 대기 중...")
        return None

    # 일치 여부 확인
    if pw1 != pw2:
        print("결과: 비밀번호가 일치하지 않음 (Mismatch)")
        return "비밀번호가 일치하지 않습니다."
    
    print("결과: 비밀번호 일치 확인 성공 (Match)")
    return None