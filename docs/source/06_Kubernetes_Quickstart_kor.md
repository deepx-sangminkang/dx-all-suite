# Kubernetes Quickstart

DEEPX DX-M1 NPU를 Kubernetes native 리소스로 사용합니다. Pod spec에
`deepx.ai/dx-m1: 1`을 선언하면 scheduler가 NPU 노드에 Pod를 배치하고, device
node와 runtime library가 자동으로 주입됩니다.

## Architecture

```
host (NPU 노드별)             k3s cluster
─────────────────────        ─────────────────────────────────────────
dx-runtime/install.sh   ──►  driver (dxrt-driver-dkms) + firmware + dxrtd
containerd CDI 활성화        (enable_cdi=true, cdi_spec_dirs에 /etc/cdi 포함)

Helm: dx-npu ──► NodeFeatureRule (PCI 1ff4 → deepx.ai/dx-m1.present)
              └► device-plugin DaemonSet → deepx.ai/dx-m1 리소스 광고
                   ├─ /etc/cdi/deepx.json 생성 (device node + libs + dxrt-cli)
                   ├─ NFD feature file 생성 → fw/driver 버전 노드 라벨
                   └─ deepx_npu_* Prometheus metrics 제공 (:9400)
Pod가 deepx.ai/dx-m1: 1 요청 → containerd가 /dev/dxrtN + runtime libs 주입
```

구성 요소 (검증된 NVIDIA 스택 구성을 동일하게 적용):

| 구성 요소 | 역할 |
|---|---|
| [dx-k8s-device-plugin](https://github.com/deepx-sangminkang/dx-k8s-device-plugin) | `deepx.ai/dx-m1` 리소스 등록, health check, Pod 할당 |
| CDI spec (plugin이 생성) | `/dev/dxrtN`, runtime libs, `dxrt-cli`를 container에 주입 |
| NFD 연동 | 노드 라벨: 장착 여부, count, product, firmware/driver 버전 |
| `dx-npu` Helm chart | 위 구성 요소 전체의 원커맨드 설치/업그레이드 |

## 사전 준비

1. **각 NPU 노드** — host driver, firmware, runtime 설치:

    ```bash
    cd dx-runtime && ./install.sh --runtime-only
    dxrt-cli -s   # NPU 목록이 표시되어야 함
    ```

2. **containerd CDI 활성화.** k3s는
   `/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl`에 추가
   (k3s는 재시작 시 `config.toml`을 재생성하므로 template을 수정):

    ```toml
    [plugins."io.containerd.grpc.v1.cri".cdi]
      enable_cdi = true
      cdi_spec_dirs = ["/etc/cdi", "/var/run/cdi"]
    ```

    이후 `systemctl restart k3s`. vanilla Kubernetes는 containerd ≥ 1.7에서
    동일한 CDI 설정이 필요합니다.

## 설치

```bash
helm install dx-npu oci://ghcr.io/deepx-sangminkang/charts/dx-npu \
  -n dx-system --create-namespace --set nfd.enabled=true
```

cluster에 node-feature-discovery가 이미 있다면 기본값(`nfd.enabled=false`)을
유지합니다.

NPU 스케줄링 가능 여부와 라벨 확인:

```bash
kubectl get node -o json | jq '.status.allocatable' | grep deepx.ai/dx-m1
kubectl get node --show-labels | grep -o 'deepx.ai[^,]*'
# deepx.ai/dx-m1.present=true, .count, .product, .fw-version, .driver-version
```

## Workload 실행

Smoke test (thin image — 모든 것이 CDI로 주입됨):

```bash
kubectl apply -f deploy/k8s/samples/test-pod.yaml
kubectl logs -f dx-m1-test
# Pod 내부에서 /dev/dxrt0 및 `dxrt-cli -s` 전체 device status 출력
```

Suite runtime image로 inference 예제 실행:

```bash
kubectl apply -f deploy/k8s/samples/dx-app-pod.yaml
kubectl logs -f dx-app-sample
```

어떤 Pod든 리소스 요청만 추가하면 NPU Pod가 됩니다:

```yaml
resources:
  limits:
    deepx.ai/dx-m1: 1
```

## Metrics

device plugin은 `:9400`에서 Prometheus metrics를 제공합니다 (headless Service
`dx-npu-metrics`): `deepx_npu_up`, `deepx_npu_device_healthy`, per-core
`deepx_npu_core_{temperature_celsius,voltage_millivolts,clock_mhz}`.
prometheus-operator가 있다면 `metrics.serviceMonitor.enabled=true`를 설정하세요.

## Troubleshooting

| 증상 | 원인 / 해결 |
|---|---|
| allocatable에 `deepx.ai/dx-m1` 없음 | device plugin Pod 미구동 — `kubectl get pods -n dx-system` 및 노드의 `deepx.ai/dx-m1.present=true` 라벨 확인 |
| `deepx.ai/*` 노드 라벨 없음 | NFD 미설치 — `nfd.enabled=true` 설정 또는 NFD 설치; NFD 없이 쓰려면 수동 라벨: `kubectl label node <n> deepx.ai/dx-m1.present=true` |
| Pod는 스케줄됐지만 `/dev/dxrt*` 없음 | containerd CDI 비활성 — config.toml.tmpl 수정 후 k3s 재시작 |
| host에서 `dxrt-cli`가 device를 못 찾음 | driver/firmware 미설치 — `dx-runtime/install.sh` 재실행, device init 실패 시 cold boot |
| device unhealthy 보고 | sysfs에는 있으나 `dxrt-cli -s`에 없음 — 대부분 host 전원 재인가 필요 |

전체 chart values와 상세 내용: `deploy/k8s/README.md`.
