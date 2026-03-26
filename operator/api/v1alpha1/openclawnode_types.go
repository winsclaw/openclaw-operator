package v1alpha1

import (
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const (
	DefaultGatewayPort  int32  = 18789
	DefaultServiceType         = corev1.ServiceTypeClusterIP
	DefaultStorageSize  string = "5Gi"
	DefaultOpenClawRepo string = "ghcr.io/openclaw/openclaw"
	DefaultOpenClawTag  string = "2026.3.2"
	DefaultChromiumRepo string = "chromedp/headless-shell"
	DefaultChromiumTag  string = "146.0.7680.31"
)

type OpenClawRuntimeSecretRef struct {
	Name string `json:"name"`
}

type OpenClawImageSpec struct {
	Repository string `json:"repository,omitempty"`
	Tag        string `json:"tag,omitempty"`
	PullPolicy string `json:"pullPolicy,omitempty"`
}

type OpenClawGatewaySpec struct {
	Port           int32                  `json:"port,omitempty"`
	ServiceType    corev1.ServiceType     `json:"serviceType,omitempty"`
	TrustedProxies []string               `json:"trustedProxies,omitempty"`
	ControlUI      *OpenClawControlUISpec `json:"controlUi,omitempty"`
}

type OpenClawControlUISpec struct {
	AllowInsecureAuth            *bool `json:"allowInsecureAuth,omitempty"`
	DangerouslyDisableDeviceAuth *bool `json:"dangerouslyDisableDeviceAuth,omitempty"`
}

type OpenClawIngressSpec struct {
	Enabled       bool              `json:"enabled,omitempty"`
	ClassName     string            `json:"className,omitempty"`
	Host          string            `json:"host,omitempty"`
	TLSSecretName string            `json:"tlsSecretName,omitempty"`
	Annotations   map[string]string `json:"annotations,omitempty"`
}

type OpenClawStorageSpec struct {
	Size             string                              `json:"size,omitempty"`
	StorageClassName *string                             `json:"storageClassName,omitempty"`
	AccessModes      []corev1.PersistentVolumeAccessMode `json:"accessModes,omitempty"`
}

type OpenClawCABundleSpec struct {
	ConfigMapName string `json:"configMapName"`
}

type OpenClawChromiumSpec struct {
	Enabled *bool             `json:"enabled,omitempty"`
	Image   OpenClawImageSpec `json:"image,omitempty"`
}

// OpenClawNodeSpec defines the desired state of OpenClawNode.
type OpenClawNodeSpec struct {
	RuntimeSecretRef OpenClawRuntimeSecretRef `json:"runtimeSecretRef"`
	Image            OpenClawImageSpec        `json:"image,omitempty"`
	Gateway          OpenClawGatewaySpec      `json:"gateway,omitempty"`
	Ingress          *OpenClawIngressSpec     `json:"ingress,omitempty"`
	Storage          OpenClawStorageSpec      `json:"storage,omitempty"`
	CABundle         *OpenClawCABundleSpec    `json:"caBundle,omitempty"`
	Chromium         *OpenClawChromiumSpec    `json:"chromium,omitempty"`
	// +kubebuilder:validation:Enum=merge;overwrite
	ConfigMode         string `json:"configMode,omitempty"`
	ServiceAccountName string `json:"serviceAccountName,omitempty"`
}

// OpenClawNodeStatus defines the observed state of OpenClawNode.
type OpenClawNodeStatus struct {
	ObservedGeneration int64              `json:"observedGeneration,omitempty"`
	Phase              string             `json:"phase,omitempty"`
	URL                string             `json:"url,omitempty"`
	ServiceName        string             `json:"serviceName,omitempty"`
	ReadyReplicas      int32              `json:"readyReplicas,omitempty"`
	Conditions         []metav1.Condition `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=openclawnodes,scope=Namespaced,shortName=ocn
// +kubebuilder:printcolumn:name="Phase",type="string",JSONPath=".status.phase"
// +kubebuilder:printcolumn:name="URL",type="string",JSONPath=".status.url"
// +kubebuilder:printcolumn:name="Ready",type="integer",JSONPath=".status.readyReplicas"

// OpenClawNode is the Schema for the openclawnodes API.
type OpenClawNode struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   OpenClawNodeSpec   `json:"spec,omitempty"`
	Status OpenClawNodeStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// OpenClawNodeList contains a list of OpenClawNode.
type OpenClawNodeList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []OpenClawNode `json:"items"`
}

func (s OpenClawNodeSpec) GatewayPort() int32 {
	if s.Gateway.Port == 0 {
		return DefaultGatewayPort
	}
	return s.Gateway.Port
}

func (s OpenClawNodeSpec) ServiceType() corev1.ServiceType {
	if s.Gateway.ServiceType == "" {
		return DefaultServiceType
	}
	return s.Gateway.ServiceType
}

func (s OpenClawNodeSpec) StorageSize() string {
	if s.Storage.Size == "" {
		return DefaultStorageSize
	}
	return s.Storage.Size
}

func (s OpenClawNodeSpec) StorageAccessModes() []corev1.PersistentVolumeAccessMode {
	if len(s.Storage.AccessModes) == 0 {
		return []corev1.PersistentVolumeAccessMode{corev1.ReadWriteOnce}
	}
	return s.Storage.AccessModes
}

func (s OpenClawNodeSpec) OpenClawImage() OpenClawImageSpec {
	image := s.Image
	if image.Repository == "" {
		image.Repository = DefaultOpenClawRepo
	}
	if image.Tag == "" {
		image.Tag = DefaultOpenClawTag
	}
	if image.PullPolicy == "" {
		image.PullPolicy = string(corev1.PullIfNotPresent)
	}
	return image
}

func (s OpenClawNodeSpec) ChromiumEnabled() bool {
	if s.Chromium == nil || s.Chromium.Enabled == nil {
		return true
	}
	return *s.Chromium.Enabled
}

func (s OpenClawNodeSpec) ChromiumImage() OpenClawImageSpec {
	if s.Chromium == nil {
		return OpenClawImageSpec{
			Repository: DefaultChromiumRepo,
			Tag:        DefaultChromiumTag,
			PullPolicy: string(corev1.PullIfNotPresent),
		}
	}
	image := s.Chromium.Image
	if image.Repository == "" {
		image.Repository = DefaultChromiumRepo
	}
	if image.Tag == "" {
		image.Tag = DefaultChromiumTag
	}
	if image.PullPolicy == "" {
		image.PullPolicy = string(corev1.PullIfNotPresent)
	}
	return image
}

func (s OpenClawNodeSpec) EffectiveConfigMode() string {
	if s.ConfigMode == "" {
		return "merge"
	}
	return s.ConfigMode
}

func init() {
	SchemeBuilder.Register(&OpenClawNode{}, &OpenClawNodeList{})
}
