package controller

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	apiMeta "k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/intstr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	appsv1alpha1 "github.com/openclaw/openclaw-operator/operator/api/v1alpha1"
)

const (
	conditionReady        = "Ready"
	conditionDependencies = "DependenciesReady"
	phasePending          = "Pending"
	phaseReady            = "Ready"
	phaseDegraded         = "Degraded"
)

// +kubebuilder:rbac:groups=apps.openclaw.io,resources=openclawnodes,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=apps.openclaw.io,resources=openclawnodes/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps.openclaw.io,resources=openclawnodes/finalizers,verbs=update
// +kubebuilder:rbac:groups="",resources=configmaps;services;persistentvolumeclaims;secrets;events,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="apps",resources=deployments,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="networking.k8s.io",resources=ingresses,verbs=get;list;watch;create;update;patch;delete

type OpenClawNodeReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

func (r *OpenClawNodeReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	node := &appsv1alpha1.OpenClawNode{}
	if err := r.Get(ctx, req.NamespacedName, node); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	if err := validateNodeSpec(node); err != nil {
		return r.updateStatus(
			ctx,
			node,
			phaseDegraded,
			"",
			0,
			metav1.ConditionFalse,
			"InvalidSpec",
			err.Error(),
			metav1.ConditionFalse,
			"InvalidSpec",
			err.Error(),
		)
	}

	if err := r.ensureDependencies(ctx, node); err != nil {
		logger.Error(err, "dependency check failed")
		return r.updateStatus(
			ctx,
			node,
			phaseDegraded,
			"",
			0,
			metav1.ConditionFalse,
			"MissingDependency",
			err.Error(),
			metav1.ConditionFalse,
			"WaitingForDependencies",
			"waiting for dependent resources",
		)
	}

	if err := r.reconcileConfigMap(ctx, node); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcilePVC(ctx, node); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcileService(ctx, node); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcileDeployment(ctx, node); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcileIngress(ctx, node); err != nil {
		return ctrl.Result{}, err
	}

	deployment := &appsv1.Deployment{}
	if err := r.Get(ctx, types.NamespacedName{Name: node.Name, Namespace: node.Namespace}, deployment); err != nil {
		return ctrl.Result{}, err
	}

	phase := phasePending
	readyStatus := metav1.ConditionFalse
	if deployment.Status.ReadyReplicas > 0 {
		phase = phaseReady
		readyStatus = metav1.ConditionTrue
	}

	return r.updateStatus(
		ctx,
		node,
		phase,
		urlForNode(node),
		deployment.Status.ReadyReplicas,
		metav1.ConditionTrue,
		"DependenciesReady",
		"dependent resources are available",
		readyStatus,
		"Reconciled",
		"resource reconciliation completed",
	)
}

func (r *OpenClawNodeReconciler) ensureDependencies(ctx context.Context, node *appsv1alpha1.OpenClawNode) error {
	secret := &corev1.Secret{}
	if err := r.Get(ctx, types.NamespacedName{Name: node.Spec.RuntimeSecretRef.Name, Namespace: node.Namespace}, secret); err != nil {
		return fmt.Errorf("runtime Secret %q not found: %w", node.Spec.RuntimeSecretRef.Name, err)
	}

	if node.Spec.CABundle != nil {
		cm := &corev1.ConfigMap{}
		if err := r.Get(ctx, types.NamespacedName{Name: node.Spec.CABundle.ConfigMapName, Namespace: node.Namespace}, cm); err != nil {
			return fmt.Errorf("CA bundle ConfigMap %q not found: %w", node.Spec.CABundle.ConfigMapName, err)
		}
	}

	return nil
}

func (r *OpenClawNodeReconciler) reconcileConfigMap(ctx context.Context, node *appsv1alpha1.OpenClawNode) error {
	configJSON, err := renderOpenClawConfig(node)
	if err != nil {
		return err
	}

	cm := &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: node.Name, Namespace: node.Namespace}}
	_, err = controllerutil.CreateOrUpdate(ctx, r.Client, cm, func() error {
		if err := controllerutil.SetControllerReference(node, cm, r.Scheme); err != nil {
			return err
		}
		cm.Labels = labelsForNode(node)
		cm.Data = map[string]string{
			"openclaw.json": configJSON,
			"bash_aliases":  "alias openclaw='node /app/dist/index.js'\n",
		}
		return nil
	})
	return err
}

func (r *OpenClawNodeReconciler) reconcilePVC(ctx context.Context, node *appsv1alpha1.OpenClawNode) error {
	pvc := &corev1.PersistentVolumeClaim{ObjectMeta: metav1.ObjectMeta{Name: node.Name, Namespace: node.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, pvc, func() error {
		if err := controllerutil.SetControllerReference(node, pvc, r.Scheme); err != nil {
			return err
		}
		pvc.Labels = labelsForNode(node)
		if pvc.CreationTimestamp.IsZero() {
			pvc.Spec.AccessModes = node.Spec.StorageAccessModes()
			pvc.Spec.StorageClassName = node.Spec.Storage.StorageClassName
		}
		pvc.Spec.Resources.Requests = corev1.ResourceList{
			corev1.ResourceStorage: resourceMustParse(node.Spec.StorageSize()),
		}
		return nil
	})
	return err
}

func (r *OpenClawNodeReconciler) reconcileService(ctx context.Context, node *appsv1alpha1.OpenClawNode) error {
	svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: node.Name, Namespace: node.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, svc, func() error {
		if err := controllerutil.SetControllerReference(node, svc, r.Scheme); err != nil {
			return err
		}
		svc.Labels = labelsForNode(node)
		svc.Spec.Type = node.Spec.ServiceType()
		svc.Spec.Selector = labelsForNode(node)
		svc.Spec.Ports = []corev1.ServicePort{{
			Name:       "http",
			Port:       node.Spec.GatewayPort(),
			TargetPort: intstr.FromInt32(node.Spec.GatewayPort()),
		}}
		return nil
	})
	return err
}

func (r *OpenClawNodeReconciler) reconcileDeployment(ctx context.Context, node *appsv1alpha1.OpenClawNode) error {
	deployment := &appsv1.Deployment{ObjectMeta: metav1.ObjectMeta{Name: node.Name, Namespace: node.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, deployment, func() error {
		if err := controllerutil.SetControllerReference(node, deployment, r.Scheme); err != nil {
			return err
		}

		labels := labelsForNode(node)
		openclawImage := node.Spec.OpenClawImage()
		chromiumImage := node.Spec.ChromiumImage()

		deployment.Labels = labels
		deployment.Spec.Replicas = int32Ptr(1)
		deployment.Spec.Selector = &metav1.LabelSelector{MatchLabels: labels}
		deployment.Spec.Strategy.Type = appsv1.RecreateDeploymentStrategyType
		deployment.Spec.Template.ObjectMeta.Labels = labels
		deployment.Spec.Template.Spec.ServiceAccountName = node.Spec.ServiceAccountName
		deployment.Spec.Template.Spec.SecurityContext = &corev1.PodSecurityContext{
			FSGroup:             int64Ptr(1000),
			FSGroupChangePolicy: fsGroupChangePolicyPtr(corev1.FSGroupChangeOnRootMismatch),
		}
		deployment.Spec.Template.Spec.EnableServiceLinks = boolPtr(false)
		deployment.Spec.Template.Spec.InitContainers = []corev1.Container{
			{
				Name:            "init-config",
				Image:           fmt.Sprintf("%s:%s", openclawImage.Repository, openclawImage.Tag),
				ImagePullPolicy: corev1.PullPolicy(openclawImage.PullPolicy),
				Command:         []string{"sh", "-c", initConfigCommand()},
				Env:             []corev1.EnvVar{{Name: "CONFIG_MODE", Value: node.Spec.EffectiveConfigMode()}},
				VolumeMounts: []corev1.VolumeMount{
					{Name: "config", MountPath: "/config", ReadOnly: true},
					{Name: "data", MountPath: "/home/node/.openclaw"},
					{Name: "tmp", MountPath: "/tmp"},
				},
			},
		}
		deployment.Spec.Template.Spec.Containers = []corev1.Container{{
			Name:            "main",
			Image:           fmt.Sprintf("%s:%s", openclawImage.Repository, openclawImage.Tag),
			ImagePullPolicy: corev1.PullPolicy(openclawImage.PullPolicy),
			Command:         []string{"node", "dist/index.js"},
			Args:            []string{"gateway", "--bind", "lan", "--port", fmt.Sprintf("%d", node.Spec.GatewayPort())},
			EnvFrom:         []corev1.EnvFromSource{{SecretRef: &corev1.SecretEnvSource{LocalObjectReference: corev1.LocalObjectReference{Name: node.Spec.RuntimeSecretRef.Name}}}},
			Ports:           []corev1.ContainerPort{{Name: "http", ContainerPort: node.Spec.GatewayPort()}},
			VolumeMounts: []corev1.VolumeMount{
				{Name: "bash-aliases", MountPath: "/home/node/.bash_aliases", SubPath: "bash_aliases", ReadOnly: true},
				{Name: "data", MountPath: "/home/node/.openclaw"},
				{Name: "tmp", MountPath: "/tmp"},
			},
			ReadinessProbe: tcpProbe(node.Spec.GatewayPort(), 10),
			LivenessProbe:  tcpProbe(node.Spec.GatewayPort(), 30),
			StartupProbe:   startupTCPProbe(node.Spec.GatewayPort()),
		}}

		if node.Spec.ChromiumEnabled() {
			deployment.Spec.Template.Spec.Containers = append(deployment.Spec.Template.Spec.Containers, corev1.Container{
				Name:            "chromium",
				Image:           fmt.Sprintf("%s:%s", chromiumImage.Repository, chromiumImage.Tag),
				ImagePullPolicy: corev1.PullPolicy(chromiumImage.PullPolicy),
				Ports:           []corev1.ContainerPort{{Name: "cdp", ContainerPort: 9222}},
				Env:             []corev1.EnvVar{{Name: "XDG_CACHE_HOME", Value: "/tmp"}},
				VolumeMounts:    []corev1.VolumeMount{{Name: "tmp", MountPath: "/tmp"}},
				ReadinessProbe:  httpProbe(9222, "/json/version", 5),
				LivenessProbe:   httpProbe(9222, "/json/version", 10),
				StartupProbe:    startupHTTPProbe(9222, "/json/version"),
			})
		}

		volumes := []corev1.Volume{
			{
				Name: "config",
				VolumeSource: corev1.VolumeSource{
					ConfigMap: &corev1.ConfigMapVolumeSource{LocalObjectReference: corev1.LocalObjectReference{Name: node.Name}},
				},
			},
			{
				Name: "bash-aliases",
				VolumeSource: corev1.VolumeSource{
					ConfigMap: &corev1.ConfigMapVolumeSource{LocalObjectReference: corev1.LocalObjectReference{Name: node.Name}},
				},
			},
			{
				Name: "data",
				VolumeSource: corev1.VolumeSource{
					PersistentVolumeClaim: &corev1.PersistentVolumeClaimVolumeSource{ClaimName: node.Name},
				},
			},
			{
				Name:         "tmp",
				VolumeSource: corev1.VolumeSource{EmptyDir: &corev1.EmptyDirVolumeSource{}},
			},
		}

		if node.Spec.CABundle != nil {
			volumes = append(volumes, caBundleVolume(node))
			addCABundleMounts(&deployment.Spec.Template.Spec, node.Spec.ChromiumEnabled())
		}

		deployment.Spec.Template.Spec.Volumes = volumes
		return nil
	})
	return err
}

func (r *OpenClawNodeReconciler) reconcileIngress(ctx context.Context, node *appsv1alpha1.OpenClawNode) error {
	if node.Spec.Ingress == nil || !node.Spec.Ingress.Enabled {
		ing := &networkingv1.Ingress{ObjectMeta: metav1.ObjectMeta{Name: node.Name, Namespace: node.Namespace}}
		if err := r.Delete(ctx, ing); client.IgnoreNotFound(err) != nil {
			return err
		}
		return nil
	}

	ing := &networkingv1.Ingress{ObjectMeta: metav1.ObjectMeta{Name: node.Name, Namespace: node.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, ing, func() error {
		if err := controllerutil.SetControllerReference(node, ing, r.Scheme); err != nil {
			return err
		}
		pathType := networkingv1.PathTypePrefix
		ing.Labels = labelsForNode(node)
		ing.Annotations = node.Spec.Ingress.Annotations
		ing.Spec.IngressClassName = optionalStringPtr(node.Spec.Ingress.ClassName)
		ing.Spec.Rules = []networkingv1.IngressRule{{
			Host: node.Spec.Ingress.Host,
			IngressRuleValue: networkingv1.IngressRuleValue{
				HTTP: &networkingv1.HTTPIngressRuleValue{
					Paths: []networkingv1.HTTPIngressPath{{
						Path:     "/",
						PathType: &pathType,
						Backend: networkingv1.IngressBackend{
							Service: &networkingv1.IngressServiceBackend{
								Name: node.Name,
								Port: networkingv1.ServiceBackendPort{Number: node.Spec.GatewayPort()},
							},
						},
					}},
				},
			},
		}}
		if node.Spec.Ingress.TLSSecretName != "" {
			ing.Spec.TLS = []networkingv1.IngressTLS{{
				Hosts:      []string{node.Spec.Ingress.Host},
				SecretName: node.Spec.Ingress.TLSSecretName,
			}}
		} else {
			ing.Spec.TLS = nil
		}
		return nil
	})
	return err
}

func (r *OpenClawNodeReconciler) updateStatus(
	ctx context.Context,
	node *appsv1alpha1.OpenClawNode,
	phase string,
	url string,
	readyReplicas int32,
	dependenciesStatus metav1.ConditionStatus,
	dependenciesReason string,
	dependenciesMessage string,
	readyStatus metav1.ConditionStatus,
	readyReason string,
	readyMessage string,
) (ctrl.Result, error) {
	original := node.DeepCopy()
	node.Status.ObservedGeneration = node.Generation
	node.Status.Phase = phase
	node.Status.URL = url
	node.Status.ServiceName = node.Name
	node.Status.ReadyReplicas = readyReplicas
	apiMeta.SetStatusCondition(&node.Status.Conditions, metav1.Condition{
		Type:               conditionDependencies,
		Status:             dependenciesStatus,
		Reason:             dependenciesReason,
		Message:            dependenciesMessage,
		ObservedGeneration: node.Generation,
		LastTransitionTime: metav1.Now(),
	})
	apiMeta.SetStatusCondition(&node.Status.Conditions, metav1.Condition{
		Type:               conditionReady,
		Status:             readyStatus,
		Reason:             readyReason,
		Message:            readyMessage,
		ObservedGeneration: node.Generation,
		LastTransitionTime: metav1.Now(),
	})

	if err := r.Status().Patch(ctx, node, client.MergeFrom(original)); err != nil {
		return ctrl.Result{}, err
	}

	if dependenciesStatus == metav1.ConditionFalse && phase == phaseDegraded {
		return ctrl.Result{RequeueAfter: time.Minute}, nil
	}
	return ctrl.Result{}, nil
}

func (r *OpenClawNodeReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&appsv1alpha1.OpenClawNode{}).
		Owns(&corev1.ConfigMap{}).
		Owns(&corev1.PersistentVolumeClaim{}).
		Owns(&corev1.Service{}).
		Owns(&appsv1.Deployment{}).
		Owns(&networkingv1.Ingress{}).
		Complete(r)
}

func labelsForNode(node *appsv1alpha1.OpenClawNode) map[string]string {
	return map[string]string{
		"app.kubernetes.io/name":      "openclaw",
		"app.kubernetes.io/instance":  node.Name,
		"app.kubernetes.io/component": "node",
		"openclaw.io/node":            node.Name,
	}
}

func validateNodeSpec(node *appsv1alpha1.OpenClawNode) error {
	if node.Spec.RuntimeSecretRef.Name == "" {
		return errors.New("spec.runtimeSecretRef.name must be set")
	}
	if node.Spec.Ingress != nil && node.Spec.Ingress.Enabled && node.Spec.Ingress.Host == "" {
		return errors.New("spec.ingress.host must be set when ingress is enabled")
	}
	switch node.Spec.EffectiveConfigMode() {
	case "merge", "overwrite":
		return nil
	default:
		return fmt.Errorf("spec.configMode must be one of: merge, overwrite")
	}
}

func renderOpenClawConfig(node *appsv1alpha1.OpenClawNode) (string, error) {
	trustedProxies := node.Spec.Gateway.TrustedProxies
	if trustedProxies == nil {
		trustedProxies = []string{}
	}
	controlUI := map[string]any{
		"dangerouslyAllowHostHeaderOriginFallback": true,
	}
	if node.Spec.Gateway.ControlUI != nil && node.Spec.Gateway.ControlUI.AllowInsecureAuth != nil {
		controlUI["allowInsecureAuth"] = *node.Spec.Gateway.ControlUI.AllowInsecureAuth
	}
	if node.Spec.Gateway.ControlUI != nil && node.Spec.Gateway.ControlUI.DangerouslyDisableDeviceAuth != nil {
		controlUI["dangerouslyDisableDeviceAuth"] = *node.Spec.Gateway.ControlUI.DangerouslyDisableDeviceAuth
	}

	config := map[string]any{
		"gateway": map[string]any{
			"port":           node.Spec.GatewayPort(),
			"mode":           "local",
			"trustedProxies": trustedProxies,
			"controlUi":      controlUI,
		},
		"browser": map[string]any{
			"enabled":        node.Spec.ChromiumEnabled(),
			"defaultProfile": "default",
			"profiles": map[string]any{
				"default": map[string]any{
					"cdpUrl": "http://localhost:9222",
					"color":  "#4285F4",
				},
			},
		},
		"agents": map[string]any{
			"defaults": map[string]any{
				"workspace": "/home/node/.openclaw/workspace",
				"model": map[string]any{
					"primary": "${OPENCLAW_PRIMARY_MODEL}",
				},
				"userTimezone":   "UTC",
				"timeoutSeconds": 600,
				"maxConcurrent":  1,
			},
			"list": []map[string]any{{
				"id":      "main",
				"default": true,
				"identity": map[string]any{
					"name": node.Name,
				},
			}},
		},
		"models": map[string]any{
			"providers": map[string]any{
				"openai": map[string]any{
					"baseUrl": "${OPENAI_BASE_URL}",
					"api":     "openai-completions",
					"models":  []any{},
				},
			},
		},
		"session": map[string]any{
			"scope": "per-sender",
			"store": "/home/node/.openclaw/sessions.json",
			"reset": map[string]any{
				"mode":        "idle",
				"idleMinutes": 60,
			},
		},
		"logging": map[string]any{
			"level":           "info",
			"consoleLevel":    "info",
			"consoleStyle":    "compact",
			"redactSensitive": "tools",
		},
		"tools": map[string]any{
			"profile": "full",
			"web": map[string]any{
				"search": map[string]any{"enabled": true},
				"fetch":  map[string]any{"enabled": true},
			},
		},
	}

	raw, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return "", err
	}
	return string(raw), nil
}

func initConfigCommand() string {
	return `set -eu
mkdir -p /home/node/.openclaw /home/node/.openclaw/workspace

if [ "${CONFIG_MODE:-merge}" = "merge" ] && [ -f /home/node/.openclaw/openclaw.json ]; then
  if node <<'EOF'
const fs = require('fs');

const existingPath = '/home/node/.openclaw/openclaw.json';
const desiredPath = '/config/openclaw.json';
const existing = JSON.parse(fs.readFileSync(existingPath, 'utf8'));
const desired = JSON.parse(fs.readFileSync(desiredPath, 'utf8'));

function deepMerge(target, source) {
  for (const [key, value] of Object.entries(source)) {
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      target[key] = target[key] || {};
      deepMerge(target[key], value);
      continue;
    }
    target[key] = value;
  }
  return target;
}

fs.writeFileSync(existingPath, JSON.stringify(deepMerge(existing, desired), null, 2));
EOF
  then
    exit 0
  fi
fi

cp /config/openclaw.json /home/node/.openclaw/openclaw.json
`
}

func caBundleVolume(node *appsv1alpha1.OpenClawNode) corev1.Volume {
	return corev1.Volume{
		Name: "ca-bundle",
		VolumeSource: corev1.VolumeSource{
			ConfigMap: &corev1.ConfigMapVolumeSource{
				LocalObjectReference: corev1.LocalObjectReference{Name: node.Spec.CABundle.ConfigMapName},
			},
		},
	}
}

func addCABundleMounts(spec *corev1.PodSpec, chromiumEnabled bool) {
	mount := corev1.VolumeMount{
		Name:      "ca-bundle",
		MountPath: "/etc/ssl/certs/ca-bundle.crt",
		SubPath:   "ca-bundle.crt",
		ReadOnly:  true,
	}
	envs := []corev1.EnvVar{
		{Name: "SSL_CERT_FILE", Value: "/etc/ssl/certs/ca-bundle.crt"},
		{Name: "NODE_EXTRA_CA_CERTS", Value: "/etc/ssl/certs/ca-bundle.crt"},
		{Name: "REQUESTS_CA_BUNDLE", Value: "/etc/ssl/certs/ca-bundle.crt"},
	}

	for i := range spec.InitContainers {
		spec.InitContainers[i].VolumeMounts = append(spec.InitContainers[i].VolumeMounts, mount)
		spec.InitContainers[i].Env = append(spec.InitContainers[i].Env, envs...)
	}
	for i := range spec.Containers {
		spec.Containers[i].VolumeMounts = append(spec.Containers[i].VolumeMounts, mount)
		spec.Containers[i].Env = append(spec.Containers[i].Env, envs...)
	}
	if !chromiumEnabled {
		return
	}
}

func resourceMustParse(value string) resource.Quantity {
	return resource.MustParse(value)
}

func int32Ptr(v int32) *int32    { return &v }
func int64Ptr(v int64) *int64    { return &v }
func boolPtr(v bool) *bool       { return &v }
func stringPtr(v string) *string { return &v }
func optionalStringPtr(v string) *string {
	if v == "" {
		return nil
	}
	return &v
}

func urlForNode(node *appsv1alpha1.OpenClawNode) string {
	if node.Spec.Ingress != nil && node.Spec.Ingress.Enabled && node.Spec.Ingress.Host != "" {
		scheme := "http"
		if node.Spec.Ingress.TLSSecretName != "" {
			scheme = "https"
		}
		return fmt.Sprintf("%s://%s", scheme, node.Spec.Ingress.Host)
	}
	return fmt.Sprintf("http://%s.%s.svc:%d", node.Name, node.Namespace, node.Spec.GatewayPort())
}

func fsGroupChangePolicyPtr(v corev1.PodFSGroupChangePolicy) *corev1.PodFSGroupChangePolicy {
	return &v
}

func tcpProbe(port int32, initialDelay int32) *corev1.Probe {
	return &corev1.Probe{
		InitialDelaySeconds: initialDelay,
		PeriodSeconds:       10,
		TimeoutSeconds:      5,
		ProbeHandler: corev1.ProbeHandler{
			TCPSocket: &corev1.TCPSocketAction{Port: intstr.FromInt32(port)},
		},
	}
}

func startupTCPProbe(port int32) *corev1.Probe {
	return &corev1.Probe{
		FailureThreshold: 30,
		PeriodSeconds:    5,
		TimeoutSeconds:   5,
		ProbeHandler: corev1.ProbeHandler{
			TCPSocket: &corev1.TCPSocketAction{Port: intstr.FromInt32(port)},
		},
	}
}

func httpProbe(port int32, path string, initialDelay int32) *corev1.Probe {
	return &corev1.Probe{
		InitialDelaySeconds: initialDelay,
		PeriodSeconds:       10,
		TimeoutSeconds:      5,
		ProbeHandler: corev1.ProbeHandler{
			HTTPGet: &corev1.HTTPGetAction{
				Path: path,
				Port: intstr.FromInt32(port),
			},
		},
	}
}

func startupHTTPProbe(port int32, path string) *corev1.Probe {
	return &corev1.Probe{
		FailureThreshold: 12,
		PeriodSeconds:    5,
		TimeoutSeconds:   5,
		ProbeHandler: corev1.ProbeHandler{
			HTTPGet: &corev1.HTTPGetAction{
				Path: path,
				Port: intstr.FromInt32(port),
			},
		},
	}
}
