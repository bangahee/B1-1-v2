# B1-1-v2: 시스템 관제 자동화 스크립트 개발

## 1. 프로젝트 개요

이 프로젝트는 Linux 서버 운영 환경에서 필요한 기본 보안 설정, 계정 및 그룹 기반 권한 관리, 애플리케이션 실행 환경 구성, 시스템 관제 자동화 스크립트 작성, 로그 누적 및 로그 보존 정책 구성을 수행한 결과물이다.

주요 목표는 단순히 Linux 명령어를 실행하는 것이 아니라, 실제 서버 운영 상황을 가정하여 SSH 보안, 방화벽 정책, 사용자 권한 분리, 애플리케이션 상태 점검, 리소스 모니터링, cron 기반 자동 실행까지 하나의 운영 환경으로 구성하는 것이다.

---

## 2. 구현 범위

본 프로젝트에서 구현한 핵심 항목은 다음과 같다.

* SSH 포트 `20022` 변경
* Root 원격 접속 차단
* UFW 방화벽 활성화
* 인바운드 허용 포트 `20022/tcp`, `15034/tcp` 제한
* `agent-admin`, `agent-dev`, `agent-test` 사용자 생성
* `agent-common`, `agent-core` 그룹 생성
* 역할 기반 디렉토리 권한 설정
* ACL 확인을 통한 권한 검증
* 제공 애플리케이션 실행 환경 구성
* `monitor.sh` Bash 스크립트 작성
* 프로세스, 포트, 방화벽, CPU, 메모리, 디스크 상태 점검
* `/var/log/agent-app/monitor.log` 로그 누적
* logrotate를 통한 `10MB / 10개 파일` 로그 보존 정책 구성
* `agent-admin` crontab을 통한 매분 자동 실행

보너스 항목인 `report.sh`와 시간 기반 아카이브 정책은 수행하지 않았다.

---

## 3. 디렉토리 구조

```text
B1-1-v2/
├── README.md
├── Dockerfile
├── .gitignore
├── bin/
│   └── monitor.sh
└── config/
    └── agent-app-monitor
```

---

## 4. 제공 앱 파일 준비

이 저장소에는 제공 애플리케이션 바이너리인 `agent-app.zip`을 포함하지 않는다.

Docker 이미지를 빌드하기 전에 과제에서 제공받은 `agent-app.zip` 파일을 프로젝트 루트 디렉토리에 직접 넣어야 한다.

예시 구조는 다음과 같다.

```text
B1-1-v2/
├── agent-app.zip
├── Dockerfile
├── README.md
├── bin/
│   └── monitor.sh
└── config/
    └── agent-app-monitor
```

`agent-app.zip` 내부에는 다음 파일이 있어야 한다.

```text
agent-app-linux-x86
agent-app-linux-arm64
```

Dockerfile은 컨테이너의 CPU 아키텍처를 확인한 뒤, `x86_64` 환경에서는 `agent-app-linux-x86`을 사용하고 ARM 환경에서는 `agent-app-linux-arm64`를 사용하도록 구성되어 있다.

---

## 5. Docker 이미지 빌드

프로젝트 루트 디렉토리에서 다음 명령어를 실행한다.

```bash
docker build -t b1-1-v2 .
```

---

## 6. Docker 컨테이너 실행

UFW 방화벽을 컨테이너 내부에서 활성화하기 위해 `NET_ADMIN`, `NET_RAW` capability를 추가한다.

```bash
docker rm -f B1-1-v2 2>/dev/null

docker run -it \
  --name B1-1-v2 \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -p 20022:20022 \
  -p 15034:15034 \
  b1-1-v2
```

컨테이너가 실행되면 SSH, UFW, cron, agent app이 자동으로 시작된다.

---

## 7. 컨테이너 내부 접속

다른 터미널 창에서 다음 명령어로 컨테이너에 접속한다.

```bash
docker exec -it B1-1-v2 /bin/bash
```

---

## 8. 검증 명령어

### 8.1 SSH 설정 확인

```bash
grep -E "^(Port|PermitRootLogin)" /etc/ssh/sshd_config
ss -tulnp | grep ssh
```

예상 결과는 다음과 같다.

```text
Port 20022
PermitRootLogin no
0.0.0.0:20022 LISTEN
```

---

### 8.2 UFW 방화벽 확인

```bash
ufw status verbose
```

예상 결과는 다음과 같다.

```text
Status: active
20022/tcp ALLOW IN Anywhere
15034/tcp ALLOW IN Anywhere
```

---

### 8.3 사용자 및 그룹 확인

```bash
id agent-admin
id agent-dev
id agent-test
```

예상 구조는 다음과 같다.

```text
agent-admin: agent-common, agent-core
agent-dev: agent-common, agent-core
agent-test: agent-common
```

---

### 8.4 디렉토리 권한 확인

```bash
ls -ld /home/agent-admin/agent-app
ls -ld /home/agent-admin/agent-app/upload_files
ls -ld /home/agent-admin/agent-app/api_keys
ls -ld /home/agent-admin/agent-app/bin
ls -ld /var/log/agent-app
```

권한 정책은 다음과 같다.

```text
upload_files      : agent-common 그룹 R/W 가능
api_keys          : agent-core 그룹만 R/W 가능
/var/log/agent-app: agent-core 그룹만 R/W 가능
bin               : agent-dev 소유, agent-core 실행 가능
```

---

### 8.5 ACL 확인

```bash
getfacl /home/agent-admin/agent-app
getfacl /home/agent-admin/agent-app/upload_files
getfacl /home/agent-admin/agent-app/api_keys
getfacl /home/agent-admin/agent-app/bin
getfacl /var/log/agent-app
```

---

### 8.6 환경 변수 확인

```bash
su - agent-admin
source ~/.bashrc

echo $AGENT_HOME
echo $AGENT_PORT
echo $AGENT_UPLOAD_DIR
echo $AGENT_KEY_PATH
echo $AGENT_LOG_DIR

cat $AGENT_KEY_PATH/secret.key
exit
```

주의할 점은 제공된 실행 파일이 `AGENT_KEY_PATH`를 개별 키 파일 경로가 아니라 `api_keys` 디렉토리 경로로 검증했다는 것이다.

따라서 본 프로젝트에서는 다음과 같이 구성하였다.

```bash
AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys
```

실제 키 파일은 다음 위치에 저장하였다.

```text
/home/agent-admin/agent-app/api_keys/secret.key
```

키 파일의 내용은 다음과 같다.

```text
agent_api_key_test
```

---

### 8.7 앱 실행 상태 확인

```bash
cat /tmp/agent_app.out
pgrep -af agent-app
ss -tulnp | grep 15034
```

예상 결과는 다음과 같다.

```text
All Boot Checks Passed!
Agent READY
0.0.0.0:15034 LISTEN
```

---

### 8.8 monitor.sh 확인

```bash
ls -l /home/agent-admin/agent-app/bin/monitor.sh
cat /home/agent-admin/agent-app/bin/monitor.sh
```

예상 권한은 다음과 같다.

```text
-rwxr-x--- agent-dev agent-core monitor.sh
```

---

### 8.9 monitor.sh 수동 실행

```bash
su - agent-admin
source ~/.bashrc
$AGENT_HOME/bin/monitor.sh
exit
```

예상 결과는 다음과 같다.

```text
[HEALTH CHECK]
Checking process 'agent-app'... [OK]
Checking port 15034... [OK]

[FIREWALL CHECK]
Checking UFW status... [OK]

[RESOURCE MONITORING]
CPU Usage : ...
MEM Usage : ...
DISK Used : ...

[INFO] Log appended: /var/log/agent-app/monitor.log
```

---

### 8.10 monitor.log 누적 확인

```bash
tail -n 10 /var/log/agent-app/monitor.log
```

로그 형식은 다음과 같다.

```text
[YYYY-MM-DD HH:MM:SS] PID:... CPU:...% MEM:...% DISK_USED:...%
```

---

### 8.11 logrotate 확인

```bash
cat /etc/logrotate.d/agent-app-monitor
logrotate -d /etc/logrotate.d/agent-app-monitor
```

적용한 정책은 다음과 같다.

```text
size 10M
rotate 10
compress
copytruncate
```

---

### 8.12 cron 자동 실행 확인

```bash
su - agent-admin
crontab -l
cat /tmp/monitor_cron.out
tail -n 10 /var/log/agent-app/monitor.log
exit
```

예상 crontab은 다음과 같다.

```cron
* * * * * /home/agent-admin/agent-app/bin/monitor.sh >> /tmp/monitor_cron.out 2>&1
```

---

## 9. monitor.sh 기능 설명

`monitor.sh`는 Bash로 작성된 시스템 관제 자동화 스크립트이다.

수행 기능은 다음과 같다.

* `agent-app` 프로세스 실행 여부 확인
* TCP `15034` 포트 LISTEN 상태 확인
* UFW 방화벽 활성화 여부 확인
* CPU 사용률 수집
* 메모리 사용률 수집
* 루트 파티션 디스크 사용률 수집
* CPU, MEM, DISK 임계값 초과 시 경고 출력
* `/var/log/agent-app/monitor.log`에 상태 로그 누적 기록

임계값은 다음과 같다.

```text
CPU       > 20%
MEM       > 10%
DISK_USED > 80%
```

프로세스 또는 포트 Health Check가 실패하면 `exit 1`로 종료한다.

방화벽과 리소스 임계값은 경고만 출력하고 스크립트는 계속 실행된다.

---

## 10. 보안 및 운영 설계 설명

SSH 포트를 기본값인 `22`에서 `20022`로 변경하고 Root 원격 접속을 차단하여 기본적인 접근 보안을 강화하였다.

UFW 방화벽은 기본적으로 인바운드를 차단하고, 서비스 운영에 필요한 `20022/tcp`와 `15034/tcp`만 허용하였다. 이를 통해 불필요한 포트 노출을 줄였다.

계정과 그룹은 역할에 따라 분리하였다. `agent-admin`은 운영 및 cron 실행자, `agent-dev`는 스크립트 작성자, `agent-test`는 테스트 사용자로 구성하였다. `agent-common`은 공유 디렉토리 접근용, `agent-core`는 핵심 보안 디렉토리 접근용으로 분리하였다.

`upload_files`는 `agent-common` 그룹이 읽고 쓸 수 있도록 설정했고, `api_keys`와 `/var/log/agent-app`는 `agent-core` 그룹만 접근할 수 있도록 하여 일반 테스트 계정이 민감한 파일과 로그에 접근하지 못하도록 구성하였다.

환경 변수는 앱 실행 위치, 포트, 업로드 경로, 키 경로, 로그 경로를 고정하기 위해 사용하였다. 이를 통해 실행 환경이 바뀌더라도 동일한 기준으로 앱과 스크립트가 동작하도록 구성하였다.

cron은 `agent-admin` 계정에 등록하여 `monitor.sh`를 매분 자동 실행하도록 설정하였다. 이를 통해 사람이 직접 명령어를 실행하지 않아도 시스템 상태가 지속적으로 기록된다.

logrotate는 `monitor.log`가 커졌을 때 `10MB` 기준으로 회전하고 최대 10개 파일을 보존하도록 설정하였다. 이를 통해 로그가 무한히 커져 디스크를 점유하는 문제를 방지하였다.
