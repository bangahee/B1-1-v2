# B1-1-v2: 시스템 관제 자동화 스크립트 개발

## 1. 프로젝트 개요

이 프로젝트는 Linux 서버 운영 환경을 가정하여 SSH 보안 설정, UFW 방화벽 구성, 사용자 및 그룹 기반 권한 분리, 애플리케이션 실행 환경 구성, 시스템 관제 자동화 스크립트 작성, 로그 누적, logrotate 기반 로그 보존 정책, cron 자동 실행을 구현한 결과물이다.

처음에는 `ubuntu:24.04` Docker 컨테이너를 직접 실행한 뒤, 컨테이너 내부에서 패키지 설치, 사용자 생성, 권한 설정, 앱 실행, `monitor.sh`, `logrotate`, `cron` 설정을 수동으로 구성하며 기능을 검증하였다.

이후 동일한 환경을 GitHub 저장소에서 재현할 수 있도록 `Dockerfile`, `bin/monitor.sh`, `config/agent-app-monitor`, `.gitignore`, `README.md` 구조로 정리하였다. 최종 제출용 저장소는 Docker 이미지를 빌드하면 필요한 Linux 운영 환경이 자동으로 구성되도록 작성하였다.

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
* 일반 Linux 권한 설정 및 getfacl을 통한 권한 상태 검증
* 환경 변수 설정
* 제공 애플리케이션 `agent-app` 실행 환경 구성
* CPU 아키텍처에 맞는 앱 바이너리 선택
* `AGENT_KEY_PATH` 검증 오류 확인 및 수정
* `monitor.sh` Bash 스크립트 작성
* 프로세스, 포트, 방화벽, CPU, 메모리, 디스크 상태 점검
* `/var/log/agent-app/monitor.log` 로그 누적
* logrotate를 통한 `10MB / 10개 파일` 로그 보존 정책 구성
* logrotate group-writable directory 문제 해결
* `agent-admin` crontab을 통한 매분 자동 실행
* Dockerfile 기반 자동 재현 환경 구성
* GitHub 제출을 위한 저장소 구조 정리

보너스 항목인 `report.sh`와 시간 기반 아카이브 정책은 필수 구현 범위에는 포함하지 않았다.

---

## 3. 최종 GitHub 저장소 구조

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

제공 애플리케이션 파일인 `agent-app.zip`은 GitHub에 업로드하지 않는다.
따라서 Docker 이미지를 빌드하기 전에 과제에서 제공받은 `agent-app.zip` 파일을 프로젝트 루트 디렉토리에 직접 넣어야 한다.

예시 구조는 다음과 같다.

```text
B1-1-v2/
├── agent-app.zip
├── README.md
├── Dockerfile
├── .gitignore
├── bin/
│   └── monitor.sh
└── config/
    └── agent-app-monitor
```

`agent-app.zip` 내부에는 다음 파일이 포함되어 있어야 한다.

```text
agent-app-linux-x86
agent-app-linux-arm64
```

Dockerfile은 컨테이너의 CPU 아키텍처를 확인한 뒤 다음 기준에 따라 실행 파일을 선택한다.

```text
x86_64        -> agent-app-linux-x86
aarch64/arm64 -> agent-app-linux-arm64
```

---

## 4. 초기 수동 구현 과정 요약

초기 검증은 `ubuntu:24.04` 컨테이너를 직접 실행하여 진행하였다.

```bash
docker rm -f B1-1 2>/dev/null

docker run -it \
  --name B1-1 \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -p 20022:20022 \
  -p 15034:15034 \
  ubuntu:24.04 /bin/bash
```

컨테이너 내부에서 다음 패키지를 설치하였다.

```bash
apt update

DEBIAN_FRONTEND=noninteractive apt install -y \
  sudo openssh-server ufw python3 vim nano iproute2 procps cron bc unzip acl file logrotate
```

이후 SSH 설정, UFW 방화벽, 사용자 및 그룹, 디렉토리 권한, ACL 확인, 환경 변수, 앱 실행, `monitor.sh`, logrotate, cron을 순서대로 구성하고 검증하였다.

초기 수동 구현 과정에서 확인한 핵심 내용은 다음과 같다.

* SSH는 `20022` 포트로 변경하였다.
* Root 원격 접속은 `PermitRootLogin no`로 차단하였다.
* UFW는 활성화하고 `20022/tcp`, `15034/tcp`만 허용하였다.
* `agent-admin`, `agent-dev`, `agent-test` 사용자를 생성하였다.
* `agent-common`, `agent-core` 그룹을 생성하였다.
* `upload_files`, `api_keys`, `bin`, `/var/log/agent-app` 디렉토리 권한을 역할별로 분리하였다.
* `getfacl`로 ACL 증빙을 확인하였다.
* 앱 실행 과정에서 `AGENT_KEY_PATH`는 개별 키 파일이 아니라 `api_keys` 디렉토리 경로여야 함을 확인하였다.
* `monitor.sh`를 작성하여 프로세스, 포트, 방화벽, CPU, 메모리, 디스크 상태를 점검하였다.
* `monitor.log`에 상태 로그가 누적되는 것을 확인하였다.
* logrotate 설정에서 group-writable directory 문제를 확인하고 `su agent-admin agent-core` 옵션을 추가하여 해결하였다.
* `agent-admin` crontab에 매분 자동 실행을 등록하였다.

---

## 5. 최종 Dockerfile 기반 구현

초기 수동 검증 후, 동일한 환경을 자동으로 재현하기 위해 Dockerfile을 작성하였다.

Dockerfile은 다음 작업을 자동으로 수행한다.

* Ubuntu 24.04 기반 이미지 사용
* 필수 패키지 설치
* SSH 보안 설정
* 사용자 및 그룹 생성
* 디렉토리 구조 및 권한 설정
* 환경 변수 등록
* `secret.key` 생성
* `monitor.sh` 복사 및 권한 설정
* logrotate 설정 파일 복사
* `agent-admin`이 `ufw status`만 비밀번호 없이 실행할 수 있도록 sudoers 설정
* `agent-app.zip` 압축 해제
* CPU 아키텍처에 맞는 앱 바이너리 선택
* `agent-admin` crontab 등록
* 컨테이너 실행 시 SSH, UFW, cron, agent app 자동 시작

---

## 6. Docker 이미지 빌드 방법

먼저 프로젝트 루트에 `agent-app.zip`을 넣는다.

```bash
cp ~/Downloads/agent-app.zip ~/B1-1-v2/agent-app.zip
```

이후 프로젝트 루트에서 Docker 이미지를 빌드한다.

```bash
cd ~/B1-1-v2
docker build -t b1-1-v2 .
```

---

## 7. Docker 컨테이너 실행 방법

기존 컨테이너가 있다면 삭제한다.

```bash
docker rm -f B1-1-v2 2>/dev/null
```

그다음 컨테이너를 실행한다.

```bash
docker run -it \
  --name B1-1-v2 \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -p 20022:20022 \
  -p 15034:15034 \
  b1-1-v2
```

UFW 방화벽을 컨테이너 내부에서 활성화하기 위해 `NET_ADMIN`, `NET_RAW` capability를 추가하였다.

컨테이너가 정상 실행되면 다음 서비스들이 자동으로 시작된다.

* SSH
* UFW
* cron
* agent app

정상 실행 시 앱 출력에서 다음 내용을 확인할 수 있다.

```text
All Boot Checks Passed!
Agent READY
Agent listening at port 15034
```

---

## 8. Dockerfile CMD 수정 사항

Dockerfile 작성 후 첫 실행 과정에서 다음 오류가 발생하였다.

```text
nohup: failed to run command '/agent-app': No such file or directory
```

이 오류는 컨테이너 시작 시 `su - agent-admin -c` 환경에서 `.bashrc`가 기대한 방식으로 로드되지 않아 `$AGENT_HOME`이 비어 있었기 때문에 발생하였다.

즉, Docker가 다음 경로를 실행하려고 했다.

```text
/agent-app
```

그러나 실제 앱 위치는 다음과 같다.

```text
/home/agent-admin/agent-app/agent-app
```

따라서 Dockerfile의 `CMD`에서는 `$AGENT_HOME/agent-app`에 의존하지 않고, 절대 경로를 사용하도록 수정하였다.

수정 후 앱은 정상적으로 실행되었고, `Agent READY`와 `15034` 포트 LISTEN 상태를 확인하였다.

---

## 9. 검증 명령어

컨테이너가 실행된 상태에서 다른 터미널을 열고 다음 명령어로 접속한다.

```bash
docker exec -it B1-1-v2 /bin/bash
```

---

### 9.1 SSH 설정 확인

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

### 9.2 UFW 방화벽 확인

```bash
ufw status verbose
```

예상 결과는 다음과 같다.

```text
Status: active
Default: deny (incoming), allow (outgoing), deny (routed)

20022/tcp ALLOW IN Anywhere
15034/tcp ALLOW IN Anywhere
20022/tcp (v6) ALLOW IN Anywhere (v6)
15034/tcp (v6) ALLOW IN Anywhere (v6)
```

---

### 9.3 사용자 및 그룹 확인

```bash
id agent-admin
id agent-dev
id agent-test
```

예상 구조는 다음과 같다.

```text
agent-admin: agent-common, agent-core
agent-dev  : agent-common, agent-core
agent-test : agent-common
```

---

### 9.4 디렉토리 권한 확인

```bash
ls -ld /home/agent-admin/agent-app
ls -ld /home/agent-admin/agent-app/upload_files
ls -ld /home/agent-admin/agent-app/api_keys
ls -ld /home/agent-admin/agent-app/bin
ls -ld /var/log/agent-app
```

권한 정책은 다음과 같다.

```text
/home/agent-admin/agent-app              : agent-admin 소유, agent-core 그룹
/home/agent-admin/agent-app/upload_files : agent-common 그룹 읽기/쓰기 가능
/home/agent-admin/agent-app/api_keys     : agent-core 그룹만 접근 가능
/home/agent-admin/agent-app/bin          : agent-dev 소유, agent-core 그룹 실행 가능
/var/log/agent-app                       : agent-core 그룹만 접근 가능
```

---

### 9.5 ACL 확인

```bash
getfacl /home/agent-admin/agent-app
getfacl /home/agent-admin/agent-app/upload_files
getfacl /home/agent-admin/agent-app/api_keys
getfacl /home/agent-admin/agent-app/bin
getfacl /var/log/agent-app
```

일반 Linux 소유자/그룹/권한 설정(chown, chmod)을 기반으로 디렉토리 접근 정책을 구성하고, 제출 증빙을 위해 getfacl 명령어로 권한 상태를 확인하였다.

---

### 9.6 환경 변수 및 키 파일 확인

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

최종 환경 변수는 다음과 같다.

```text
AGENT_HOME=/home/agent-admin/agent-app
AGENT_PORT=15034
AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files
AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys
AGENT_LOG_DIR=/var/log/agent-app
```

키 파일 위치는 다음과 같다.

```text
/home/agent-admin/agent-app/api_keys/secret.key
```

키 파일 내용은 다음과 같다.

```text
agent_api_key_test
```

---

### 9.7 앱 실행 상태 확인

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

### 9.8 monitor.sh 확인

```bash
ls -l /home/agent-admin/agent-app/bin/monitor.sh
cat /home/agent-admin/agent-app/bin/monitor.sh
```

예상 권한은 다음과 같다.

```text
-rwxr-x--- 1 agent-dev agent-core ... monitor.sh
```

---

### 9.9 monitor.sh 수동 실행

```bash
su - agent-admin
source ~/.bashrc
$AGENT_HOME/bin/monitor.sh
exit
```

예상 결과는 다음과 같다.

```text
====== SYSTEM MONITOR RESULT ======

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

### 9.10 monitor.log 누적 확인

```bash
tail -n 10 /var/log/agent-app/monitor.log
```

로그 형식은 다음과 같다.

```text
[YYYY-MM-DD HH:MM:SS] PID:... CPU:...% MEM:...% DISK_USED:...%
```

실제 검증 과정에서 다음과 같은 로그가 누적되는 것을 확인하였다.

```text
[2026-06-09 07:03:01] PID:1 CPU:0.0% MEM:5.2% DISK_USED:1%
[2026-06-09 07:03:36] PID:1 CPU:0.0% MEM:5.1% DISK_USED:1%
```

---

### 9.11 logrotate 확인

```bash
cat /etc/logrotate.d/agent-app-monitor
logrotate -d /etc/logrotate.d/agent-app-monitor
```

최종 logrotate 설정은 다음과 같다.

```text
/var/log/agent-app/monitor.log {
su agent-admin agent-core
size 10M
rotate 10
missingok
notifempty
compress
copytruncate
}
```

처음에는 `/var/log/agent-app` 디렉토리가 group-writable이기 때문에 다음 오류가 발생하였다.

```text
error: skipping "/var/log/agent-app/monitor.log" because parent directory has insecure permissions
```

이 문제는 디렉토리 권한을 변경하지 않고, logrotate 설정에 다음 항목을 추가하여 해결하였다.

```text
su agent-admin agent-core
```

---

### 9.12 cron 자동 실행 확인

```bash
su - agent-admin
crontab -l
cat /tmp/monitor_cron.out
tail -n 10 /var/log/agent-app/monitor.log
exit
```

등록된 crontab은 다음과 같다.

```cron
* * * * * /home/agent-admin/agent-app/bin/monitor.sh >> /tmp/monitor_cron.out 2>&1
```

cron 실행 결과는 `/tmp/monitor_cron.out`에 기록되고, `/var/log/agent-app/monitor.log`에도 매분 상태 로그가 누적된다.

---

## 10. monitor.sh 기능 설명

`monitor.sh`는 Bash로 작성한 시스템 관제 자동화 스크립트이다.

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

방화벽 상태와 리소스 임계값은 경고를 출력하지만, 스크립트 자체는 계속 실행되도록 구성하였다.

---

## 11. 보안 및 운영 설계 설명

SSH 포트를 기본값인 `22`에서 `20022`로 변경하고 Root 원격 접속을 차단하여 기본적인 접근 보안을 강화하였다.

UFW 방화벽은 기본적으로 인바운드를 차단하고, 서비스 운영에 필요한 `20022/tcp`와 `15034/tcp`만 허용하였다. 이를 통해 불필요한 포트 노출을 줄였다.

계정과 그룹은 역할에 따라 분리하였다. `agent-admin`은 운영 및 cron 실행자, `agent-dev`는 스크립트 작성자, `agent-test`는 테스트 사용자로 구성하였다. `agent-common`은 공유 디렉토리 접근용, `agent-core`는 핵심 보안 디렉토리 접근용으로 분리하였다.

`upload_files`는 `agent-common` 그룹이 읽고 쓸 수 있도록 설정했고, `api_keys`와 `/var/log/agent-app`는 `agent-core` 그룹만 접근할 수 있도록 하여 일반 테스트 계정이 민감한 파일과 로그에 접근하지 못하도록 구성하였다.

`monitor.sh`는 `agent-admin`의 cron으로 실행되지만, 방화벽 상태 확인에는 root 권한이 필요했기 때문에 `/etc/sudoers.d/agent-monitor`에 `ufw status` 명령어만 비밀번호 없이 실행할 수 있도록 제한적으로 허용하였다.

환경 변수는 앱 실행 위치, 포트, 업로드 경로, 키 경로, 로그 경로를 고정하기 위해 사용하였다. 특히 실제 앱 검증 과정에서 `AGENT_KEY_PATH`가 개별 키 파일이 아니라 `api_keys` 디렉토리 경로를 가리켜야 한다는 점을 확인하고 수정하였다.

Dockerfile의 `CMD`에서는 `$AGENT_HOME`이 컨테이너 시작 시 비어 있는 문제가 발생했기 때문에, 앱 실행 명령어를 절대 경로인 `/home/agent-admin/agent-app/agent-app`로 수정하였다. 이를 통해 `.bashrc` 로드 여부와 관계없이 앱이 안정적으로 실행되도록 구성하였다.

logrotate는 `monitor.log`가 커졌을 때 `10MB` 기준으로 회전하고 최대 10개 파일을 보존하도록 설정하였다. 또한 `/var/log/agent-app`가 group-writable 디렉토리이기 때문에 logrotate 설정에 `su agent-admin agent-core`를 추가하여 정상적으로 동작하도록 수정하였다.

cron은 `agent-admin` 계정에 등록하여 `monitor.sh`를 매분 자동 실행하도록 설정하였다. 이를 통해 사람이 직접 명령어를 실행하지 않아도 시스템 상태가 지속적으로 기록되도록 구성하였다.

---

## 12. GitHub 업로드 시 제외한 파일

제공받은 앱 바이너리 파일은 GitHub에 업로드하지 않았다.

`.gitignore`에는 다음 항목을 포함하였다.

```text
agent-app.zip
agent-app-linux-x86
agent-app-linux-arm64
__MACOSX/

*.log
monitor_cron.out
agent_app.out

.DS_Store
```

따라서 저장소를 clone한 사용자는 Docker 이미지를 빌드하기 전에 직접 `agent-app.zip`을 프로젝트 루트에 넣어야 한다.

---

## 13. 최종 검증 항목

최종적으로 다음 항목을 확인하였다.

* SSH 포트가 `20022`로 변경되었는가?
* Root 원격 접속이 차단되었는가?
* UFW가 활성화되어 있는가?
* UFW에서 `20022/tcp`, `15034/tcp`만 허용되는가?
* `agent-admin`, `agent-dev`, `agent-test` 사용자가 생성되었는가?
* `agent-common`, `agent-core` 그룹이 생성되었는가?
* 사용자별 그룹 권한이 요구사항대로 설정되었는가?
* `/home/agent-admin/agent-app` 하위 디렉토리 권한이 역할별로 분리되었는가?
* ACL 확인 결과가 설정한 권한과 일치하는가?
* `AGENT_HOME`, `AGENT_PORT`, `AGENT_UPLOAD_DIR`, `AGENT_KEY_PATH`, `AGENT_LOG_DIR` 환경 변수가 설정되었는가?
* `secret.key`가 올바른 위치에 생성되었는가?
* CPU 아키텍처에 맞는 `agent-app` 실행 파일을 선택했는가?
* 앱 Boot Sequence가 모두 `[OK]`로 통과했는가?
* `Agent READY`가 출력되었는가?
* `agent-app`이 `15034` 포트에서 LISTEN 상태인가?
* `monitor.sh`가 프로세스, 포트, 방화벽, 리소스 상태를 점검하는가?
* 프로세스 또는 포트 오류 시 `exit 1`로 종료되도록 구성되었는가?
* `/var/log/agent-app/monitor.log`에 로그가 누적되는가?
* logrotate 정책이 `10MB / 10개 파일` 기준으로 설정되었는가?
* logrotate 설정에 `su agent-admin agent-core`가 추가되어 있는가?
* `agent-admin` crontab에 매분 자동 실행이 등록되었는가?
* cron 실행 결과가 `/tmp/monitor_cron.out`에 기록되는가?
* Dockerfile 기반으로 동일 환경을 재현할 수 있는가?
