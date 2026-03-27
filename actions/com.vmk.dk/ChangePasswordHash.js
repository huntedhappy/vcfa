import crypt
import time

def handler(context, inputs):
    plain_pw = inputs.get("passwd")
    
    # 1. 입력값 체크 및 로그 (보안을 위해 첫 글자만 로그에 남김)
    if not plain_pw:
        print("로그: 입력된 패스워드가 없습니다.")
        return ""
    
    print(f"로그: 패스워드 해싱 시작 (입력 길이: {len(plain_pw)})")
    
    # 2. SHA-512 ($6$) 해시 생성
    start_time = time.time()
    hashed_pw = crypt.crypt(plain_pw, crypt.mksalt(crypt.METHOD_SHA512))
    end_time = time.time()
    
    # 3. 완료 로그
    print(f"로그: 해싱 완료 (소요시간: {end_time - start_time:.4f}s)")
    
    return hashed_pw