# Kubernetes NGAP Load Balancing with loxilb

This branch contains Kubernetes manifests for deploying Open5GS AMF with:
- **loxilb** as the SCTP-aware ServiceLB
- **HPA** (Horizontal Pod Autoscaler) for utilization-based auto-scaling

## Architecture

```
                         ┌─────────────────────────────────────────┐
                         │            Kubernetes Cluster           │
                         │                                         │
    gNB ──NGAP/SCTP──►  │  ┌──────────────────────────────────┐   │
         (38412)         │  │  loxilb (DaemonSet)              │   │
                         │  │  - SCTP load balancing           │   │
                         │  │  - Least-connections selection   │   │
                         │  └──────────────────────────────────┘   │
                         │                  │                      │
                         │      ┌───────────┴───────────┐          │
                         │      ▼                       ▼          │
                         │  ┌───────┐              ┌───────┐       │
                         │  │AMF-1  │              │AMF-2  │       │
                         │  │(Pod)  │              │(Pod)  │       │
                         │  └───────┘              └───────┘       │
                         │      ▲                       ▲          │
                         │      └───────────┬───────────┘          │
                         │                  │                      │
                         │        ┌─────────┴─────────┐            │
                         │        │  HPA              │            │
                         │        │  - Scale on CPU   │            │
                         │        │  - Scale on Mem   │            │
                         │        └───────────────────┘            │
                         └─────────────────────────────────────────┘
```

## Prerequisites

1. **Kubernetes cluster** (minikube, kind, k3s, or cloud-based)
2. **kubectl** configured to access your cluster
3. **metrics-server** installed for HPA to work:
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
   ```

## Deployment

### Quick Start
```bash
./setup-k8s-ngap-lb.sh deploy
```

### Step by Step
```bash
# 1. Check prerequisites
./setup-k8s-ngap-lb.sh prereq

# 2. Deploy loxilb load balancer
./setup-k8s-ngap-lb.sh deploy-lb

# 3. Deploy Open5GS AMF with HPA
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/amf-configmap.yaml
kubectl apply -f k8s/amf-deployment.yaml
kubectl apply -f k8s/amf-hpa.yaml
```

## HPA Configuration

The HPA is configured to scale AMF pods based on resource utilization:

| Metric | Threshold | Action |
|--------|-----------|--------|
| CPU | > 70% | Scale up |
| Memory | > 80% | Scale up |
| Min Replicas | 1 | Always at least 1 pod |
| Max Replicas | 5 | Never more than 5 pods |

### Scale Behavior
- **Scale Up**: Immediate (0s stabilization)
- **Scale Down**: Wait 5 minutes before scaling down

## Testing Auto-Scaling

```bash
# Run built-in stress test
./setup-k8s-ngap-lb.sh scale-test

# Or manually stress a pod
kubectl exec -it <amf-pod> -n open5gs -- stress --cpu 2 --timeout 120

# Watch HPA respond
kubectl get hpa amf-hpa -n open5gs -w
```

## Monitoring

```bash
# Check deployment status
./setup-k8s-ngap-lb.sh status

# Watch pods scale
kubectl get pods -n open5gs -w

# Check HPA metrics
kubectl describe hpa amf-hpa -n open5gs

# View loxilb LB rules
kubectl exec -it <loxilb-pod> -n kube-system -- loxicmd get lb
```

## Files

| File | Description |
|------|-------------|
| `k8s/namespace.yaml` | open5gs namespace |
| `k8s/amf-configmap.yaml` | AMF configuration |
| `k8s/amf-deployment.yaml` | AMF Deployment + Service |
| `k8s/amf-hpa.yaml` | Horizontal Pod Autoscaler |
| `k8s/loxilb-daemonset.yaml` | loxilb DaemonSet |
| `k8s/kube-loxilb.yaml` | kube-loxilb controller + RBAC |
| `setup-k8s-ngap-lb.sh` | Deployment script |

## Cleanup

```bash
./setup-k8s-ngap-lb.sh cleanup
```

## Comparison with Docker Setup

| Feature | Docker | Kubernetes |
|---------|--------|------------|
| Load Balancing | Manual loxicmd | Automatic via Service |
| Scaling | Manual docker run | Automatic via HPA |
| Utilization-based | ❌ | ✅ (CPU/Memory triggers) |
| Self-healing | ❌ | ✅ (Pod restart on failure) |
| Service Discovery | Manual IPs | Automatic DNS |
