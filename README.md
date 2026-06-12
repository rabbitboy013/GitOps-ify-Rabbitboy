# GitOps-ify-Rabbitboy

Lab GitOps chạy local trên Windows với Minikube, ArgoCD, Argo Rollouts,
Prometheus và Alertmanager.

Repo minh họa đầy đủ các luồng:

- App-of-apps: một ArgoCD `root` Application quản lý các Application con.
- Frontend và backend được tách riêng.
- Flask API có `/metrics`, được triển khai bằng Argo Rollout canary.
- Prometheus scrape API thông qua `ServiceMonitor`.
- Alertmanager gửi cảnh báo thử nghiệm tới Gmail.
- Git là nguồn sự thật; ArgoCD tự sync, prune và self-heal Kubernetes.

> Repo đã được tối ưu cho Docker Desktop chỉ có khoảng 3 GB RAM. Grafana,
> default Prometheus rules, kube-state-metrics và node-exporter hiện đang tắt
> để cụm local ổn định hơn.

## Kiến trúc

```text
GitHub main
    |
    v
ArgoCD root Application
    |
    +-- backend                -> k8s/backend/
    +-- frontend               -> k8s/frontend/
    +-- api                    -> k8s-api/
    +-- argo-rollouts          -> Helm chart
    +-- kube-prometheus-stack  -> Helm chart
    +-- monitoring-lab         -> monitoring/

Browser
    |
    v
Frontend Service -> Frontend Pod -> Backend Service -> Backend Pod

Prometheus -> ServiceMonitor -> API Service -> API Rollout Pods -> /metrics

EmailTestAlert -> Prometheus -> Alertmanager -> Gmail
```

## Cấu trúc Repo

```text
.
|-- app/
|   |-- app.py
|   |-- Dockerfile
|   `-- requirements.txt
|-- argocd/
|   |-- root.yaml
|   `-- apps/
|       |-- api.yaml
|       |-- argo-rollouts.yaml
|       |-- backend.yaml
|       |-- frontend.yaml
|       |-- kube-prometheus-stack.yaml
|       `-- monitoring-lab.yaml
|-- k8s/
|   |-- backend/backend.yaml
|   `-- frontend/frontend.yaml
|-- k8s-api/
|   |-- api.yaml
|   `-- servicemonitor.yaml
|-- monitoring/
|   `-- email-test-rule.yaml
|-- scripts/
|   `-- configure-alertmanager-email.ps1
`-- .github/workflows/validate.yml
```

## Thành Phần Đang Chạy

| Thành phần | Namespace | Chức năng |
|---|---|---|
| `root` | `argocd` | App-of-apps, quản lý Application con |
| `frontend` | `demo` | Nginx phục vụ UI và gọi backend |
| `backend` | `demo` | HTTP echo backend đơn giản |
| `api` | `demo` | Flask API triển khai bằng Argo Rollout |
| `argo-rollouts` | `argo-rollouts` | Canary controller và dashboard |
| `kube-prometheus-stack` | `monitoring` | Prometheus, Operator và Alertmanager |
| `monitoring-lab` | `monitoring` | PrometheusRule test email |

API Flask hỗ trợ:

```text
GET /         JSON response và VERSION
GET /healthz  readiness endpoint
GET /metrics  Prometheus metrics
```

## Yêu Cầu

- Windows 11 và PowerShell.
- Docker Desktop.
- `kubectl`.
- Minikube.
- Git.
- Một repository GitHub public hoặc ArgoCD đã được cấp quyền đọc repo private.
- Gmail App Password nếu muốn test email.

Kiểm tra công cụ:

```powershell
docker version
kubectl version --client
minikube version
git --version
```

## Khởi Động Hằng Ngày

Đây là luồng dùng khi profile Minikube `w9` và ArgoCD đã được tạo trước đó.

### 1. Khởi động Docker Desktop

```powershell
docker desktop start
docker version
```

Nếu Docker Desktop đang paused, chọn **Resume** trong Docker Desktop hoặc chạy:

```powershell
docker desktop restart
```

### 2. Khởi động cụm Minikube

```powershell
minikube start -p w9 --driver=docker
kubectl config use-context w9
minikube status -p w9
kubectl get nodes
```

Kết quả mong đợi:

```text
w9   Ready
```

### 3. Kiểm tra ArgoCD và workload

Sau khi cụm vừa lên, chờ khoảng 1-3 phút:

```powershell
kubectl -n argocd get pods
kubectl -n argocd get applications
kubectl -n demo get deployments,pods,services
kubectl -n monitoring get pods
```

Các Application cuối cùng nên là `Synced` và `Healthy`. Trên máy ít RAM,
trạng thái có thể tạm thời là `Unknown` hoặc `Progressing` trong lúc pod khởi
động.

### 4. Kiểm tra image API local

API dùng image local `w9-api:1`, không lấy từ registry:

```powershell
minikube image ls -p w9 | Select-String "w9-api"
```

Nếu chưa có:

```powershell
docker build -t w9-api:1 app
minikube image load w9-api:1 -p w9
```

## Dựng Lại Từ Đầu

Dùng phần này khi profile `w9` đã bị xóa hoặc triển khai trên máy mới.

### 1. Tạo cụm

```powershell
minikube start -p w9 --driver=docker
kubectl config use-context w9
kubectl get nodes
```

Nếu Docker Desktop được cấp đủ RAM, khuyến nghị 4 CPU và 6 GB:

```powershell
minikube start -p w9 --driver=docker --cpus=4 --memory=6g
```

Không dùng `--memory=6g` nếu Docker Desktop chỉ được cấp khoảng 3 GB.

### 2. Build và load API image

```powershell
docker build -t w9-api:1 app
minikube image load w9-api:1 -p w9
minikube image ls -p w9 | Select-String "w9-api"
```

### 3. Cài ArgoCD

```powershell
kubectl create namespace argocd

kubectl apply --server-side -n argocd `
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl -n argocd rollout status deployment/argocd-server --timeout=10m
kubectl -n argocd get pods
```

### 4. Bootstrap root Application

Đây là lần `kubectl apply` thủ công duy nhất cần thiết cho app-of-apps:

```powershell
kubectl apply -f argocd/root.yaml
kubectl -n argocd get applications
```

Từ đây, root sẽ tự tạo các Application con từ `argocd/apps/`.

### 5. Tạo lại Gmail Secret

Secret và App Password không nằm trong Git. Chạy lại:

```powershell
.\scripts\configure-alertmanager-email.ps1
```

## Truy Cập Localhost

Mỗi lệnh port-forward phải được giữ chạy trong terminal riêng. Nhấn `Ctrl+C`
để dừng.

| Giao diện | Lệnh | URL |
|---|---|---|
| ArgoCD | `kubectl -n argocd port-forward svc/argocd-server 8080:443` | `https://localhost:8080` |
| Frontend | `kubectl -n demo port-forward svc/frontend 8081:80` | `http://localhost:8081` |
| API | `kubectl -n demo port-forward svc/api 18080:8080` | `http://localhost:18080` |
| Prometheus | `kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090` | `http://localhost:9090` |
| Alertmanager | `kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093` | `http://localhost:9093` |
| Rollouts Dashboard | `kubectl -n argo-rollouts port-forward svc/argo-rollouts-dashboard 3100:3100` | `http://localhost:3100` |

Grafana hiện bị tắt để giảm RAM. Muốn bật lại, sửa:

```yaml
grafana:
  enabled: true
```

trong `argocd/apps/kube-prometheus-stack.yaml`, rồi commit/push. Nên tăng RAM
Docker Desktop trước khi bật.

### Đăng nhập ArgoCD

Username:

```text
admin
```

Lấy mật khẩu:

```powershell
$secret = kubectl -n argocd get secret argocd-initial-admin-secret `
  -o jsonpath="{.data.password}"

[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($secret))
```

## Luồng GitOps

Luồng thay đổi chuẩn:

```text
Sửa manifest
    -> git commit
    -> git push main
    -> ArgoCD phát hiện thay đổi
    -> ArgoCD sync Kubernetes
```

Ví dụ scale backend:

```powershell
# Sửa replicas trong k8s/backend/backend.yaml
git add k8s/backend/backend.yaml
git commit -m "scale backend"
git push origin main

kubectl -n demo get deployment backend -w
```

Các Application đã bật:

```yaml
automated:
  prune: true
  selfHeal: true
```

- `automated`: tự sync thay đổi từ Git.
- `prune`: tự xóa resource không còn trong Git.
- `selfHeal`: tự sửa cluster về trạng thái trong Git nếu có chỉnh tay.

Không nên dùng `kubectl apply` trực tiếp cho manifest app thông thường. Mọi
thay đổi lâu dài nên đi qua Git.

## Test Frontend Và Backend

Mở frontend:

```powershell
kubectl -n demo port-forward svc/frontend 8081:80
```

Truy cập:

```text
http://localhost:8081
```

Kết quả mong đợi:

```text
GitOps Frontend
Hello from the GitOps backend
```

Test backend trực tiếp:

```powershell
kubectl -n demo port-forward svc/backend 5678:5678
```

Terminal khác:

```powershell
Invoke-RestMethod http://localhost:5678
```

## Test Flask API

### Test image bằng Docker

```powershell
docker run --rm -p 18080:8080 --name w9-api-test w9-api:1
```

Terminal khác:

```powershell
Invoke-RestMethod http://localhost:18080/
Invoke-WebRequest http://localhost:18080/healthz -UseBasicParsing
Invoke-WebRequest http://localhost:18080/metrics -UseBasicParsing
```

Kết quả mong đợi:

```json
{"ok": true, "version": "v2"}
```

Image được build với default `v1`; workload Kubernetes hiện truyền
`VERSION=v2`.

### Test API trong Kubernetes

```powershell
kubectl -n demo port-forward svc/api 18080:8080
Invoke-RestMethod http://localhost:18080/
```

## Prometheus Và Metrics

ServiceMonitor `k8s-api/servicemonitor.yaml` yêu cầu Prometheus scrape:

```text
Service api -> port http -> /metrics -> mỗi 15 giây
```

Mở Prometheus:

```powershell
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```

Query target API:

```promql
up{namespace="demo", service="api"}
```

Query tổng request:

```promql
sum(flask_http_request_total{namespace="demo"})
```

Tạo traffic thử nghiệm:

```powershell
kubectl -n demo run api-load `
  --image=busybox:1.36 `
  --restart=Never `
  --command -- sh -c 'for i in $(seq 1 100); do wget -qO- http://api:8080/ >/dev/null; done'

kubectl -n demo wait --for=jsonpath='{.status.phase}'=Succeeded pod/api-load --timeout=2m
kubectl -n demo delete pod api-load
```

## Canary Với Argo Rollouts

Rollout hiện có các bước:

```text
25% -> pause thủ công -> 50% -> chờ 30 giây -> 100%
```

Do không cấu hình traffic router chuyên dụng, tỷ lệ canary được mô phỏng bằng
tỷ lệ pod:

```text
25% ~= 1 pod mới + 3 pod cũ
```

### Kích hoạt revision mới

Đổi `VERSION` trong `k8s-api/api.yaml`, ví dụ:

```yaml
- name: VERSION
  value: "v3"
```

Sau đó:

```powershell
git add k8s-api/api.yaml
git commit -m "release API v3 canary"
git push origin main
```

Theo dõi:

```powershell
kubectl -n demo get rollout api -w
kubectl -n demo get pods -l app=api -L rollouts-pod-template-hash
```

Hoặc mở Rollouts Dashboard:

```powershell
kubectl -n argo-rollouts port-forward svc/argo-rollouts-dashboard 3100:3100
```

### Promote hoặc abort

Nếu đã cài plugin `kubectl-argo-rollouts`:

```powershell
kubectl argo rollouts get rollout api -n demo --watch
kubectl argo rollouts promote api -n demo
kubectl argo rollouts abort api -n demo
```

Nếu chưa cài plugin, dùng Rollouts Dashboard để promote/abort.

## Alertmanager Gửi Gmail

### Cấu hình email an toàn

Không commit Gmail App Password vào Git. Chạy:

```powershell
.\scripts\configure-alertmanager-email.ps1
```

Script hỏi:

```text
Gmail address used to send and receive the test alert:
Gmail App Password (input is hidden):
```

Google thường hiển thị App Password theo nhóm có dấu cách. Khi nhập có thể bỏ
dấu cách. Không dùng mật khẩu Gmail chính nếu Google từ chối SMTP.

Script tạo trực tiếp trong cluster:

- Secret `monitoring/alertmanager-email`.
- AlertmanagerConfig `monitoring/email-test`.

Secret không được lưu trong Git và phải tạo lại nếu dựng cluster mới.

### Kiểm tra cấu hình email

```powershell
kubectl -n monitoring get secret alertmanager-email
kubectl -n monitoring get alertmanagerconfig email-test
kubectl -n monitoring get alertmanager kube-prometheus-stack-alertmanager
```

Kiểm tra log gửi mail:

```powershell
kubectl -n monitoring logs alertmanager-kube-prometheus-stack-alertmanager-0 `
  -c alertmanager --since=15m |
  Select-String "Notify success|Notify attempt failed|smtp|email"
```

Thành công:

```text
msg="Notify success"
```

### Alert test

`monitoring/email-test-rule.yaml` tạo `EmailTestAlert`:

```promql
vector(1)
```

Alert luôn firing sau một phút và email được lặp lại mỗi giờ theo
`repeatInterval: 1h`.

Kiểm tra trong Prometheus:

```promql
ALERTS{alertname="EmailTestAlert", alertstate="firing"}
```

Khi không cần test nữa, đổi:

```yaml
expr: vector(0)
```

rồi commit/push để alert resolved và dừng email lặp:

```powershell
git add monitoring/email-test-rule.yaml
git commit -m "disable email test alert"
git push origin main
```

Xóa credential khỏi cluster:

```powershell
kubectl -n monitoring delete secret alertmanager-email
kubectl -n monitoring delete alertmanagerconfig email-test
```

## CI Validation

Workflow `.github/workflows/validate.yml` chạy kubeconform khi Pull Request thay
đổi file trong `k8s/**`.

Luồng khuyến nghị:

```text
branch riêng -> Pull Request -> validate pass -> merge main -> ArgoCD deploy
```

Hiện workflow chỉ validate `k8s/**`. Các CRD trong `k8s-api/**` như Rollout và
ServiceMonitor cần schema bổ sung nếu muốn mở rộng CI.

## Dừng Môi Trường

Dừng các terminal port-forward bằng `Ctrl+C`.

Dừng cụm nhưng giữ dữ liệu/profile:

```powershell
minikube stop -p w9
```

Khởi động lại:

```powershell
minikube start -p w9 --driver=docker
```

Không chạy `minikube delete -p w9` trừ khi muốn xóa toàn bộ cluster, ArgoCD,
Secret email và image local trong node.

## Troubleshooting

### Docker Desktop paused hoặc chưa chạy

Triệu chứng:

```text
Docker Desktop is manually paused
failed to connect to the docker API
```

Khắc phục:

```powershell
docker desktop restart
docker version
minikube start -p w9 --driver=docker
```

### Context `w9` không tồn tại

Triệu chứng:

```text
error: no context exists with the name: "w9"
```

Profile chưa được tạo. Chạy:

```powershell
minikube start -p w9 --driver=docker
kubectl config use-context w9
```

### Kubernetes API TLS handshake timeout

Triệu chứng:

```text
Unable to connect to the server: net/http: TLS handshake timeout
```

Nguyên nhân thường là Docker Desktop thiếu RAM/CPU.

Kiểm tra:

```powershell
docker stats w9 --no-stream
minikube status -p w9
```

Khắc phục:

1. Dừng các port-forward không cần thiết.
2. Giữ Grafana và monitoring component nặng ở trạng thái tắt.
3. Chờ cụm giảm tải.
4. Restart profile nếu cần:

```powershell
minikube stop -p w9
minikube start -p w9 --driver=docker
```

Nếu có thể, tăng Docker Desktop memory lên khoảng 6 GB.

### ArgoCD port-forward báo connection refused

Triệu chứng:

```text
socat ... 127.0.0.1:8080: Connection refused
error: lost connection to pod
```

Kiểm tra:

```powershell
kubectl -n argocd get pods
kubectl -n argocd get endpoints argocd-server
```

Service phải có endpoint và pod server phải `1/1 Running`.

Khắc phục:

```powershell
kubectl -n argocd rollout restart deployment/argocd-server
kubectl -n argocd rollout status deployment/argocd-server --timeout=5m
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

### ArgoCD Application báo `Unknown`

Kiểm tra condition:

```powershell
kubectl -n argocd get application root -o yaml
```

Nếu repo-server lỗi:

```powershell
kubectl -n argocd rollout restart deployment/argocd-repo-server
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=5m
```

Yêu cầu refresh:

```powershell
kubectl -n argocd annotate application root `
  argocd.argoproj.io/refresh=hard --overwrite
```

Nếu condition báo timeout GitHub, kiểm tra mạng và thử refresh lại sau.

### API báo `ImagePullBackOff`

API dùng image local. Build và load lại:

```powershell
docker build -t w9-api:1 app
minikube image load w9-api:1 -p w9
kubectl -n demo get pods -l app=api
```

Manifest phải giữ:

```yaml
imagePullPolicy: IfNotPresent
```

### Prometheus không thấy API

Kiểm tra:

```powershell
kubectl -n demo get service api
kubectl -n demo get servicemonitor api
kubectl -n demo get pods -l app=api
```

Service phải có named port `http`, vì ServiceMonitor tham chiếu:

```yaml
endpoints:
  - port: http
    path: /metrics
```

Query:

```promql
up{namespace="demo", service="api"}
```

### Email không được gửi

Kiểm tra alert firing:

```promql
ALERTS{alertname="EmailTestAlert", alertstate="firing"}
```

Kiểm tra receiver:

```powershell
kubectl -n monitoring get alertmanagerconfig email-test
kubectl -n monitoring get secret alertmanager-email
```

Kiểm tra log:

```powershell
kubectl -n monitoring logs alertmanager-kube-prometheus-stack-alertmanager-0 `
  -c alertmanager --since=15m |
  Select-String "Notify success|Notify attempt failed|smtp|email"
```

Các trường hợp thường gặp:

- `receiver=null`: Alertmanager chưa chọn `AlertmanagerConfig email-test`.
- `authentication failed`: Gmail từ chối credential; dùng Gmail App Password.
- `send STARTTLS command: EOF`: lỗi mạng tạm thời; Alertmanager sẽ retry.
- `Notify success`: Alertmanager đã gửi; kiểm tra Inbox và Spam.

### Port-forward thường xuyên mất kết nối

Port-forward phụ thuộc pod đang Ready. Khi pod restart, kết nối cũ sẽ mất.

```powershell
kubectl -n <namespace> get pods
kubectl -n <namespace> port-forward svc/<service> <local-port>:<service-port>
```

Không mở nhiều port-forward cùng lúc trên máy ít RAM.

## Bảo Mật

- Không commit Gmail App Password, token hoặc Kubernetes Secret vào Git.
- Không gửi App Password trong chat hoặc lưu trong file text.
- Nếu credential bị lộ, thu hồi App Password tại Google Account và tạo lại.
- Secret `alertmanager-email` chỉ tồn tại trong cluster local.
- Repo public không được chứa thông tin đăng nhập.

## Trạng Thái Tối Ưu Cho Máy Local

Cấu hình hiện tại cố ý tắt:

- Grafana.
- kube-state-metrics.
- node-exporter.
- default Prometheus rules.
- Alertmanager mặc định trước đây đã được bật lại để test email.

Các thành phần được giữ:

- ArgoCD.
- Argo Rollouts.
- Frontend/backend/API.
- Prometheus.
- Prometheus Operator.
- Alertmanager.
- ServiceMonitor API.
- EmailTestAlert.

Mục tiêu là giữ đủ chức năng GitOps, metrics, canary và email alert trong giới
hạn tài nguyên Docker Desktop local.
